import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "app.mailreveal.utility", category: "Routing")
    private let processStartedAt = DispatchTime.now().uptimeNanoseconds
    private var receivedURLs = false
    private var pendingURLs: [(url: URL, receivedAt: UInt64)] = []
    private var isProcessing = false

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
        processNextURL()
    }

    private func processNextURL() {
        guard !isProcessing else { return }
        guard !pendingURLs.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        isProcessing = true
        let pendingURL = pendingURLs.removeFirst()

        do {
            let messageLink = try MessageLink(url: pendingURL.url)
            logPhase("url-parsed", since: pendingURL.receivedAt)
            let accessibility = try MailAccessibility()
            logPhase("accessibility-ready", since: pendingURL.receivedAt)
            let automation = try MailAutomation()
            logPhase("automation-ready", since: pendingURL.receivedAt)
            let mailContext = try accessibility.context()
            logPhase("mail-context-ready", since: pendingURL.receivedAt)
            let indexed = try EnvelopeIndexResolver().resolve(messageID: messageLink.messageID)
            logPhase("index-resolution-complete", since: pendingURL.receivedAt)
            try automation.positionIndexedMessage(indexed, viewerID: mailContext.viewerID)
            logPhase("conversation-positioned", since: pendingURL.receivedAt)

            let resolved = ResolvedMailMessage(indexedMessage: indexed)
            let selectionRoute = try accessibility.selectConversation(
                resolved,
                viewerID: mailContext.viewerID
            )
            logger.notice("conversation-selection-route=\(selectionRoute.rawValue, privacy: .public)")
            logPhase("conversation-row-ready", since: pendingURL.receivedAt)
            if selectionRoute == .conversation {
                try automation.selectMessage(
                    libraryID: indexed.libraryID,
                    expectedMessageID: indexed.messageID,
                    viewerID: mailContext.viewerID
                )
                logPhase("conversation-child-selected", since: pendingURL.receivedAt)
            }
            try accessibility.raiseViewer(viewerID: mailContext.viewerID)
            logger.notice("Mail selected the linked message")

            isProcessing = false
            processNextURL()
        } catch {
            report(error)
            isProcessing = false
            processNextURL()
        }
    }

    private func logPhase(_ phase: String, since start: UInt64) {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let elapsedMilliseconds = elapsedNanoseconds / 1_000_000
        logger.notice(
            "phase=\(phase, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
        )
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
