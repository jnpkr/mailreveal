import Carbon
import Foundation

@MainActor
final class MailAutomation {
    private let script: NSAppleScript

    init(bundle: Bundle = .main) throws {
        guard let scriptURL = bundle.url(forResource: "RevealMessage", withExtension: "scpt") else {
            throw MailAutomationError.missingScript
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(contentsOf: scriptURL, error: &error) else {
            throw MailAutomationError.scriptFailure(Self.message(from: error))
        }

        self.script = script
    }

    func selectMailbox(
        accountName: String,
        mailboxName: String,
        viewerID: Int
    ) throws {
        _ = try execute(
            handler: "selectKnownMailbox",
            arguments: [
                accountName,
                mailboxName,
                String(viewerID),
            ]
        )
    }

    func positionCurrentMessage(
        expectedMessageID: String,
        viewerID: Int
    ) throws -> Int {
        let result = try execute(
            handler: "positionCurrentMessage",
            arguments: [
                expectedMessageID,
                String(viewerID),
            ]
        )
        guard
            let value = result.stringValue,
            let libraryID = Int(value)
        else {
            throw MailAutomationError.invalidLibraryID
        }
        return libraryID
    }

    func selectMessage(
        libraryID: Int,
        expectedMessageID: String,
        viewerID: Int
    ) throws {
        let result = try execute(
            handler: "selectKnownMessage",
            arguments: [
                String(libraryID),
                expectedMessageID,
                String(viewerID),
            ]
        )
        guard result.stringValue == expectedMessageID else {
            throw MailAutomationError.messageIDVerificationFailed
        }
    }

    func positionIndexedMessage(
        _ message: IndexedMailMessage,
        viewerID: Int
    ) throws {
        guard let location = message.mailboxLocation else {
            throw MailAutomationError.invalidMailboxLocation
        }
        let result = try execute(
            handler: "positionIndexedMessage",
            arguments: [
                String(message.libraryID),
                message.messageID,
                location.accountID,
                location.path,
                String(viewerID),
            ]
        )
        guard result.stringValue == message.messageID else {
            throw MailAutomationError.messageIDVerificationFailed
        }
    }

    private func execute(
        handler: String,
        arguments: [String] = []
    ) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(
            NSAppleEventDescriptor(string: handler),
            forKeyword: AEKeyword(keyASSubroutineName)
        )

        let argumentList = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            argumentList.insert(
                NSAppleEventDescriptor(string: argument),
                at: index + 1
            )
        }
        event.setParam(argumentList, forKeyword: AEKeyword(keyDirectObject))

        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if error != nil {
            throw MailAutomationError.scriptFailure(Self.message(from: error))
        }

        return result
    }

    private static func message(from error: NSDictionary?) -> String {
        if let message = error?[NSAppleScript.errorMessage] as? String {
            return message
        }
        if let briefMessage = error?[NSAppleScript.errorBriefMessage] as? String {
            return briefMessage
        }
        if let error {
            return error.description
        }
        return "Mail automation failed for an unknown reason."
    }
}

enum MailAutomationError: LocalizedError {
    case missingScript
    case invalidLibraryID
    case invalidMailboxLocation
    case messageIDVerificationFailed
    case scriptFailure(String)

    var diagnosticCode: String {
        switch self {
        case .missingScript: "missing-script"
        case .invalidLibraryID: "invalid-library-id"
        case .invalidMailboxLocation: "invalid-mailbox-location"
        case .messageIDVerificationFailed: "message-id-verification-failed"
        case .scriptFailure: "script-failure"
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "MailReveal’s bundled Mail automation script is missing."
        case .invalidLibraryID:
            return "Mail did not return the resolved message’s library ID."
        case .invalidMailboxLocation:
            return "MailReveal could not determine the indexed message’s account and mailbox."
        case .messageIDVerificationFailed:
            return "Mail returned a different Message-ID for the indexed message, so MailReveal refused to select it."
        case let .scriptFailure(message):
            return message
        }
    }
}
