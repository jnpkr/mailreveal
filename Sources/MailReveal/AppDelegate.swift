import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "app.mailreveal.utility", category: "Routing")
    private let processStartedAt = DispatchTime.now().uptimeNanoseconds
    private var receivedURLs = false
    private var pendingURLs: [(url: URL, receivedAt: UInt64)] = []
    private var processingTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logPhase("app-ready", since: processStartedAt)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.receivedURLs else { return }
            NSApp.terminate(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURLs = true
        let receivedAt = DispatchTime.now().uptimeNanoseconds
        logger.notice("phase=url-received")
        pendingURLs.append(contentsOf: urls.map { ($0, receivedAt) })

        // Links which arrive while one is being revealed join the queue and are
        // drained by the running task.
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            await self?.processPendingURLs()
            NSApp.terminate(nil)
        }
    }

    private func processPendingURLs() async {
        while !pendingURLs.isEmpty {
            let pendingURL = pendingURLs.removeFirst()
            do {
                try reveal(pendingURL.url, receivedAt: pendingURL.receivedAt)
            } catch {
                await handleFailure(error, url: pendingURL.url)
            }
        }
    }

    private func reveal(_ url: URL, receivedAt: UInt64) throws {
        let messageLink = try MessageLink(url: url)
        logPhase("url-parsed", since: receivedAt)
        let accessibility = try MailAccessibility()
        logPhase("accessibility-ready", since: receivedAt)
        let automation = try MailAutomation()
        logPhase("automation-ready", since: receivedAt)
        let mailContext = try accessibility.context()
        logPhase("mail-context-ready", since: receivedAt)
        let indexed = try EnvelopeIndexResolver().resolve(messageID: messageLink.messageID)
        logPhase("index-resolution-complete", since: receivedAt)
        try automation.positionIndexedMessage(indexed, viewerID: mailContext.viewerID)
        logPhase("conversation-positioned", since: receivedAt)

        let resolved = ResolvedMailMessage(indexedMessage: indexed)
        let selectionRoute = try accessibility.selectConversation(
            resolved,
            viewerID: mailContext.viewerID
        )
        logger.notice("conversation-selection-route=\(selectionRoute.rawValue, privacy: .public)")
        logPhase("conversation-row-ready", since: receivedAt)
        if selectionRoute == .conversation {
            try automation.selectMessage(
                libraryID: indexed.libraryID,
                expectedMessageID: indexed.messageID,
                viewerID: mailContext.viewerID
            )
            logPhase("conversation-child-selected", since: receivedAt)
        }
        try accessibility.raiseViewer(viewerID: mailContext.viewerID)
        logger.notice("Mail selected the linked message")
    }

    private func logPhase(_ phase: String, since start: UInt64) {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let elapsedMilliseconds = elapsedNanoseconds / 1_000_000
        logger.notice(
            "phase=\(phase, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
        )
    }

    private func handleFailure(_ error: Error, url: URL) async {
        report(error)

        // A malformed link means nothing to Mail either. Anything else is handed
        // to Mail so the link still opens, in Mail's own message window.
        let fallsBackToMail = !(error is MessageLinkError)
        showAlert(for: error, fallsBackToMail: fallsBackToMail)
        if fallsBackToMail {
            await openInMail(url)
        }
    }

    private func showAlert(for error: Error, fallsBackToMail: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = fallsBackToMail
            ? "MailReveal could not select the message in your viewer"
            : "MailReveal could not open this link"
        var informativeText = error.localizedDescription
        if fallsBackToMail {
            informativeText += "\n\nMail will open the message in its own window instead."
        }
        alert.informativeText = informativeText
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func openInMail(_ url: URL) async {
        guard let mailURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.mail"
        ) else {
            logger.error("MailReveal fallback failed code=mail-not-found")
            return
        }

        do {
            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: mailURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            logger.notice("Handed the link to Mail")
        } catch {
            logger.error("MailReveal fallback failed code=mail-open-failed")
        }
    }

    private func report(_ error: Error) {
        let errorCode: String
        if let error = error as? MailAccessibilityError {
            errorCode = error.diagnosticCode
        } else if let error = error as? MailAutomationError {
            errorCode = error.diagnosticCode
        } else if let error = error as? EnvelopeIndexError {
            errorCode = error.diagnosticCode
        } else if let error = error as? MessageLinkError {
            errorCode = error.diagnosticCode
        } else {
            errorCode = "unexpected-error"
        }
        logger.error("MailReveal failed code=\(errorCode, privacy: .public)")
    }
}
