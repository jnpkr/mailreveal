import AppKit
import ApplicationServices
import OSLog

private final class AXSelectionSignal {
    let runLoop: CFRunLoop

    init(runLoop: CFRunLoop) {
        self.runLoop = runLoop
    }
}

private func mailSelectionObserverCallback(
    _: AXObserver,
    _: AXUIElement,
    _: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let signal = Unmanaged<AXSelectionSignal>.fromOpaque(refcon).takeUnretainedValue()
    CFRunLoopStop(signal.runLoop)
}

struct ResolvedMailWindow {
    let message: ResolvedMailMessage
    fileprivate let element: AXUIElement
}

struct MailContext: Equatable {
    let viewerID: Int
    let windowIdentifiers: Set<String>
}

enum ConversationSelectionRoute: String {
    case message = "message-row"
    case conversation = "conversation-row"
}

@MainActor
final class MailAccessibility {
    private let logger = Logger(
        subsystem: "app.mailreveal.utility",
        category: "Accessibility"
    )
    private let applicationElement: AXUIElement
    private let mailProcessIdentifier: pid_t

    init(promptForPermission: Bool = false) throws {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: promptForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw MailAccessibilityError.permissionRequired
        }

        guard let mail = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.mail"
        ).first else {
            throw MailAccessibilityError.mailIsNotRunning
        }

        mailProcessIdentifier = mail.processIdentifier
        applicationElement = AXUIElementCreateApplication(mail.processIdentifier)
    }

    func context() throws -> MailContext {
        let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: applicationElement) ?? []
        let windowIdentifiers = Set(windows.compactMap {
            attribute(kAXIdentifierAttribute, from: $0) as String?
        })

        for window in windows where findElement(
            in: window,
            identifier: "Mail.messageList"
        ) != nil {
            guard
                let identifier: String = attribute(kAXIdentifierAttribute, from: window),
                let viewerID = MailWindowIdentifier.viewerID(from: identifier)
            else {
                continue
            }
            return MailContext(
                viewerID: viewerID,
                windowIdentifiers: windowIdentifiers
            )
        }

        throw MailAccessibilityError.viewerNotFound
    }

    func waitForResolvedMessage(
        excluding knownWindowIdentifiers: Set<String>,
        timeout: TimeInterval = 2
    ) throws -> ResolvedMailWindow {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let windows: [AXUIElement] =
                attribute(kAXWindowsAttribute, from: applicationElement) ?? []
            for window in windows {
                guard
                    let identifier: String = attribute(kAXIdentifierAttribute, from: window),
                    identifier.hasPrefix("Mail.messageViewer.window."),
                    !knownWindowIdentifiers.contains(identifier),
                    let resolved = resolvedMessage(in: window)
                else {
                    continue
                }
                return ResolvedMailWindow(message: resolved, element: window)
            }

            if
                let focusedWindow: AXUIElement = attribute(
                    kAXFocusedWindowAttribute,
                    from: applicationElement
                ),
                let identifier: String = attribute(
                    kAXIdentifierAttribute,
                    from: focusedWindow
                ),
                identifier.hasPrefix("Mail.messageViewer.window."),
                findElement(in: focusedWindow, identifier: "Mail.messageList") == nil,
                let resolved = resolvedMessage(in: focusedWindow)
            {
                // Mail may reuse a standalone window which existed before this
                // request. The focused resolver is still the right window even
                // though its identifier was present in the initial snapshot.
                return ResolvedMailWindow(message: resolved, element: focusedWindow)
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline

        throw MailAccessibilityError.resolvedWindowNotFound
    }

    func close(_ resolvedWindow: ResolvedMailWindow) throws {
        let deadline = Date().addingTimeInterval(0.4)
        repeat {
            if
                let closeButton: AXUIElement = attribute(
                    kAXCloseButtonAttribute,
                    from: resolvedWindow.element
                ),
                AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
            {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline

        throw MailAccessibilityError.couldNotCloseResolvedWindow
    }

    func raise(_ resolvedWindow: ResolvedMailWindow) throws {
        guard AXUIElementPerformAction(
            resolvedWindow.element,
            kAXRaiseAction as CFString
        ) == .success else {
            throw MailAccessibilityError.couldNotRaiseResolvedWindow
        }
    }

    func selectConversation(
        _ message: ResolvedMailMessage,
        viewerID: Int
    ) throws -> ConversationSelectionRoute {
        guard !message.subject.isEmpty else {
            throw MailAccessibilityError.missingSubject
        }

        guard let row = try waitForSelectedTargetRow(
            subject: message.subject,
            viewerID: viewerID,
            timeout: 0.45
        ) else {
            throw MailAccessibilityError.messageRowNotFound
        }

        guard
            let viewer = viewerElement(viewerID: viewerID),
            let messageTable = findElement(in: viewer, identifier: "Mail.messageList")
        else {
            throw MailAccessibilityError.viewerNotFound
        }

        try select(row, in: messageTable)

        guard let disclosure = findElement(
            in: row,
            identifier: "Mail.messageList.cell.view.disclosureButton"
        ) else {
            return .message
        }

        let expanded: Bool = {
            if let value: Bool = attribute(kAXValueAttribute, from: disclosure) {
                return value
            }
            if let value: NSNumber = attribute(kAXValueAttribute, from: disclosure) {
                return value.boolValue
            }
            return false
        }()
        if !expanded {
            guard AXUIElementPerformAction(
                disclosure,
                kAXPressAction as CFString
            ) == .success else {
                throw MailAccessibilityError.couldNotExpandConversation
            }
        }
        return .conversation
    }

    func focusMessage(_ message: ResolvedMailMessage, viewerID: Int) throws {
        try focus(message, viewerID: viewerID)
    }

    func raiseViewer(viewerID: Int) throws {
        guard
            let viewer = viewerElement(viewerID: viewerID),
            AXUIElementPerformAction(viewer, kAXRaiseAction as CFString) == .success
        else {
            throw MailAccessibilityError.couldNotRaiseViewer
        }
    }

    private func waitForSelectedTargetRow(
        subject: String,
        viewerID: Int,
        timeout: TimeInterval
    ) throws -> AXUIElement? {
        guard
            let viewer = viewerElement(viewerID: viewerID),
            let messageTable = findElement(in: viewer, identifier: "Mail.messageList")
        else {
            throw MailAccessibilityError.viewerNotFound
        }

        guard let runLoop = CFRunLoopGetCurrent() else {
            throw MailAccessibilityError.couldNotObserveSelection(.failure)
        }
        let signal = AXSelectionSignal(runLoop: runLoop)
        var observer: AXObserver?
        let createResult = AXObserverCreate(
            mailProcessIdentifier,
            mailSelectionObserverCallback,
            &observer
        )
        guard createResult == .success, let observer else {
            throw MailAccessibilityError.couldNotObserveSelection(createResult)
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(runLoop, source, .defaultMode)
        let refcon = Unmanaged.passUnretained(signal).toOpaque()
        let addResult = AXObserverAddNotification(
            observer,
            messageTable,
            kAXSelectedRowsChangedNotification as CFString,
            refcon
        )
        guard addResult == .success || addResult == .notificationAlreadyRegistered else {
            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
            throw MailAccessibilityError.couldNotObserveSelection(addResult)
        }
        defer {
            AXObserverRemoveNotification(
                observer,
                messageTable,
                kAXSelectedRowsChangedNotification as CFString
            )
            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let selectedRows: [AXUIElement] =
                attribute(kAXSelectedRowsAttribute, from: messageTable) ?? []
            if let row = selectedRows.first(where: {
                MailSubject.rowLabel(strings(in: $0).joined(separator: " "), matches: subject)
            }) {
                logger.notice("mail-selected-target-row-ready")
                return row
            }

            let visibleRows: [AXUIElement] =
                attribute("AXVisibleRows", from: messageTable) ?? []
            if let row = visibleRows.first(where: {
                MailSubject.rowLabel(strings(in: $0).joined(separator: " "), matches: subject)
            }) {
                logger.notice("mail-visible-target-row-ready visible_row_count=\(visibleRows.count)")
                return row
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            CFRunLoopRunInMode(.defaultMode, min(remaining, 0.1), true)
        } while Date() < deadline

        return nil
    }

    private func focus(_ message: ResolvedMailMessage, viewerID: Int) throws {
        guard let viewer = viewerElement(viewerID: viewerID) else {
            throw MailAccessibilityError.viewerNotFound
        }

        let deadline = Date().addingTimeInterval(1.2)
        repeat {
            let candidates = findElements(in: viewer, identifier: "message_view")
            if let target = candidates.first(where: { matches(message, in: $0) }) {
                if scrollToVisible(target) {
                    return
                }
                throw MailAccessibilityError.couldNotRevealMessage
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline

        throw MailAccessibilityError.resolvedMessageNotVisible
    }

    private func matches(_ message: ResolvedMailMessage, in element: AXUIElement) -> Bool {
        guard let header = findElement(in: element, identifier: "message_header") else {
            return false
        }

        let timestampElement = findElement(in: element, identifier: "message.timestamp")
            ?? findElement(in: element, identifier: "message.mailbox")
        let visibleTimestamp: String = timestampElement.flatMap {
            attribute(kAXValueAttribute, from: $0)
        } ?? ""

        let content = MailSubject.normalized(strings(in: header).joined(separator: " "))
        let subject = MailSubject.conversationTitle(message.subject)
        let sender = MailSubject.normalized(message.sender)
        let timestamp = MailSubject.normalized(message.timestamp)

        return content.contains(subject)
            && (sender.isEmpty || content.contains(sender))
            && (timestamp.isEmpty || MailTimestamp.matches(timestamp, in: visibleTimestamp))
    }

    private func scrollToVisible(_ root: AXUIElement) -> Bool {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var queueIndex = 0
        var visited: Set<CFHashCode> = []

        while queueIndex < queue.count {
            let (element, depth) = queue[queueIndex]
            queueIndex += 1
            guard depth <= 8, visited.insert(CFHash(element)).inserted else {
                continue
            }

            if AXUIElementPerformAction(
                element,
                "AXScrollToVisible" as CFString
            ) == .success {
                return true
            }

            let children: [AXUIElement] =
                attribute(kAXChildrenAttribute, from: element) ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }

        return false
    }

    private func select(_ row: AXUIElement, in table: AXUIElement) throws {
        let isSelected: Bool = attribute(kAXSelectedAttribute, from: row) ?? false
        if isSelected {
            return
        }

        let tableSelectionResult = AXUIElementSetAttributeValue(
            table,
            kAXSelectedRowsAttribute as CFString,
            [row] as CFArray
        )
        if tableSelectionResult == .success {
            return
        }

        let pressResult = AXUIElementPerformAction(row, kAXPressAction as CFString)
        if pressResult == .success {
            return
        }

        let selectionResult = AXUIElementSetAttributeValue(
            row,
            kAXSelectedAttribute as CFString,
            kCFBooleanTrue
        )
        guard selectionResult == .success else {
            logger.error("mail-table-row-selection-failed error=\(tableSelectionResult.rawValue)")
            throw MailAccessibilityError.couldNotSelectRow(pressResult, selectionResult)
        }
    }

    private func resolvedMessage(in window: AXUIElement) -> ResolvedMailMessage? {
        guard
            let windowTitle: String = attribute(kAXTitleAttribute, from: window),
            let mailboxElement = findElement(in: window, identifier: "message.mailbox"),
            let mailboxLabel: String = attribute(kAXValueAttribute, from: mailboxElement),
            let timestampElement = findElement(in: window, identifier: "message.timestamp"),
            let timestamp: String = attribute(kAXValueAttribute, from: timestampElement),
            let headerElement = findElement(in: window, identifier: "message.header.content"),
            let senderElement = findElement(in: headerElement, identifier: "_MAIL_TEXT_ATTACHMENT"),
            let sender: String = attribute(kAXValueAttribute, from: senderElement)
        else {
            return nil
        }

        return try? ResolvedMailMessage(
            windowTitle: windowTitle,
            mailboxLabel: mailboxLabel,
            sender: sender,
            timestamp: timestamp
        )
    }

    private func findElement(
        in root: AXUIElement,
        identifier: String? = nil,
        subrole: String? = nil
    ) -> AXUIElement? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var queueIndex = 0
        var visited: Set<CFHashCode> = []

        while queueIndex < queue.count {
            let (element, depth) = queue[queueIndex]
            queueIndex += 1

            guard depth <= 12, visited.insert(CFHash(element)).inserted else {
                continue
            }

            if let identifier {
                let candidateIdentifier: String? = attribute(
                    kAXIdentifierAttribute,
                    from: element
                )
                if candidateIdentifier == identifier {
                    return element
                }
            }

            if let subrole {
                let candidateSubrole: String? = attribute(kAXSubroleAttribute, from: element)
                if candidateSubrole == subrole {
                    return element
                }
            }

            let children: [AXUIElement] =
                attribute(kAXChildrenAttribute, from: element) ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }

        return nil
    }

    private func findElements(in root: AXUIElement, identifier: String) -> [AXUIElement] {
        var matches: [AXUIElement] = []
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var queueIndex = 0
        var visited: Set<CFHashCode> = []

        while queueIndex < queue.count {
            let (element, depth) = queue[queueIndex]
            queueIndex += 1
            guard depth <= 12, visited.insert(CFHash(element)).inserted else {
                continue
            }

            let candidateIdentifier: String? = attribute(
                kAXIdentifierAttribute,
                from: element
            )
            if candidateIdentifier == identifier {
                matches.append(element)
                continue
            }

            let children: [AXUIElement] =
                attribute(kAXChildrenAttribute, from: element) ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }

        return matches
    }

    private func strings(in root: AXUIElement) -> [String] {
        var visited: Set<CFHashCode> = []
        return strings(in: root, depth: 0, visited: &visited)
    }

    private func strings(
        in root: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>
    ) -> [String] {
        guard depth <= 6, visited.insert(CFHash(root)).inserted else {
            return []
        }

        var result: [String] = []
        for attributeName in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value: String = attribute(attributeName, from: root), !value.isEmpty {
                result.append(value)
            }
        }

        let role: String? = attribute(kAXRoleAttribute, from: root)
        if role == "AXWebArea" {
            return result
        }

        let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: root) ?? []
        for child in children {
            result.append(contentsOf: strings(in: child, depth: depth + 1, visited: &visited))
        }
        return result
    }

    private func viewerElement(viewerID: Int) -> AXUIElement? {
        let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: applicationElement) ?? []
        let identifier = "Mail.messageViewer.window.\(viewerID)"
        return windows.first { window in
            let candidateIdentifier: String? = attribute(kAXIdentifierAttribute, from: window)
            return candidateIdentifier == identifier
        }
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

}

enum MailAccessibilityError: LocalizedError {
    case permissionRequired
    case mailIsNotRunning
    case missingSubject
    case resolvedWindowNotFound
    case couldNotCloseResolvedWindow
    case couldNotRaiseResolvedWindow
    case couldNotRaiseViewer
    case couldNotObserveSelection(AXError)
    case couldNotExpandConversation
    case viewerNotFound
    case searchFieldNotFound
    case messageRowNotFound
    case resolvedMessageNotVisible
    case couldNotRevealMessage
    case couldNotSelectRow(AXError, AXError)
    case couldNotSetSearch(AXError, AXError)
    case couldNotConfirmSearch

    var diagnosticCode: String {
        switch self {
        case .permissionRequired: "accessibility-permission-required"
        case .mailIsNotRunning: "mail-not-running"
        case .missingSubject: "missing-subject"
        case .resolvedWindowNotFound: "resolved-window-not-found"
        case .couldNotCloseResolvedWindow: "could-not-close-resolved-window"
        case .couldNotRaiseResolvedWindow: "could-not-raise-resolved-window"
        case .couldNotRaiseViewer: "could-not-raise-viewer"
        case .couldNotObserveSelection: "could-not-observe-selection"
        case .couldNotExpandConversation: "could-not-expand-conversation"
        case .viewerNotFound: "viewer-not-found"
        case .searchFieldNotFound: "search-field-not-found"
        case .messageRowNotFound: "message-row-not-found"
        case .resolvedMessageNotVisible: "resolved-message-not-visible"
        case .couldNotRevealMessage: "could-not-reveal-message"
        case .couldNotSelectRow: "could-not-select-row"
        case .couldNotSetSearch: "could-not-set-search"
        case .couldNotConfirmSearch: "could-not-confirm-search"
        }
    }

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "MailReveal needs Accessibility permission to select the exact message row. Enable MailReveal in System Settings > Privacy & Security > Accessibility, then open the link again."
        case .mailIsNotRunning:
            return "Apple Mail is not running."
        case .missingSubject:
            return "The linked message has no subject to match in Mail’s message list."
        case .resolvedWindowNotFound:
            return "Mail did not open the linked message."
        case .couldNotCloseResolvedWindow:
            return "MailReveal could not close Mail’s temporary message window."
        case .couldNotRaiseResolvedWindow:
            return "MailReveal could not bring Mail’s resolved message window forward."
        case .couldNotRaiseViewer:
            return "MailReveal could not bring Mail’s main message viewer forward."
        case let .couldNotObserveSelection(error):
            return "MailReveal could not observe Mail’s selected message row (\(error.rawValue))."
        case .couldNotExpandConversation:
            return "MailReveal found the conversation but could not expand it."
        case .viewerNotFound:
            return "MailReveal could not find Mail’s main message viewer."
        case .searchFieldNotFound:
            return "MailReveal could not find Mail’s search field."
        case .messageRowNotFound:
            return "MailReveal found the message in Mail but could not find its row in the message list."
        case .resolvedMessageNotVisible:
            return "Mail selected the conversation but did not display the linked message."
        case .couldNotRevealMessage:
            return "Mail displayed the linked message but would not scroll it into view."
        case let .couldNotSelectRow(pressError, selectionError):
            return "Mail’s message row could not be selected (\(pressError.rawValue), \(selectionError.rawValue))."
        case let .couldNotSetSearch(valueError, focusError):
            return "Mail’s search field could not be updated (\(valueError.rawValue), \(focusError.rawValue))."
        case .couldNotConfirmSearch:
            return "MailReveal could not start Mail’s message search."
        }
    }
}
