import Foundation

struct ResolvedMailMessage: Equatable {
    let subject: String
    let sender: String
    let timestamp: String
    let mailboxName: String
    let accountName: String

    init(indexedMessage: IndexedMailMessage) {
        subject = indexedMessage.subject
        sender = indexedMessage.sender
        if let received = indexedMessage.received {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = "d MMMM yyyy 'at' HH:mm"
            timestamp = formatter.string(from: received)
        } else {
            timestamp = ""
        }
        mailboxName = indexedMessage.mailboxLocation?.path ?? ""
        accountName = indexedMessage.mailboxLocation?.accountID ?? ""
    }

    init(
        windowTitle: String,
        mailboxLabel: String,
        sender: String,
        timestamp: String
    ) throws {
        guard let separator = windowTitle.range(of: " – ", options: .backwards) else {
            throw ResolvedMailMessageError.invalidWindowTitle
        }

        let subject = windowTitle[..<separator.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let accountName = windowTitle[separator.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !accountName.isEmpty else {
            throw ResolvedMailMessageError.invalidWindowTitle
        }

        var mailboxName = mailboxLabel
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for accountSeparator in [" - ", " – "] {
            let suffix = accountSeparator + accountName
            if mailboxName.hasSuffix(suffix) {
                mailboxName.removeLast(suffix.count)
                mailboxName = mailboxName.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard !mailboxName.isEmpty else {
            throw ResolvedMailMessageError.invalidMailboxLabel
        }

        self.subject = subject
        self.sender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timestamp = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mailboxName = mailboxName
        self.accountName = accountName
    }
}

enum MailSubject {
    static func rowLabel(_ rowLabel: String, matches subject: String) -> Bool {
        normalized(String(rowLabel.prefix(512))).contains(conversationTitle(subject))
    }

    static func conversationTitle(_ subject: String) -> String {
        var result = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["re:", "fwd:", "fw:"]

        while let prefix = prefixes.first(where: {
            result.lowercased().hasPrefix($0)
        }) {
            result.removeFirst(prefix.count)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized(result)
    }

    static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

struct MailTimestamp: Equatable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int

    static func matches(_ target: String, in mailboxLabel: String) -> Bool {
        let normalizedTarget = MailSubject.normalized(target)
        let normalizedLabel = MailSubject.normalized(mailboxLabel)
        if normalizedLabel.contains(normalizedTarget) {
            return true
        }

        guard
            let targetTimestamp = parse(from: target),
            let labelTimestamp = parse(from: mailboxLabel)
        else {
            return false
        }
        return targetTimestamp == labelTimestamp
    }

    static func parse(from value: String) -> MailTimestamp? {
        if let numeric = captures(
            pattern: #"(\d{1,2})/(\d{1,2})/(\d{4})\s+at\s+(\d{1,2}):(\d{2})"#,
            in: value
        ),
            let day = Int(numeric[0]),
            let month = Int(numeric[1]),
            let year = Int(numeric[2]),
            let hour = Int(numeric[3]),
            let minute = Int(numeric[4])
        {
            return MailTimestamp(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        }

        guard
            let named = captures(
                pattern: #"(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\s+at\s+(\d{1,2}):(\d{2})"#,
                in: value
            ),
            let day = Int(named[0]),
            let month = monthNumber(named[1]),
            let year = Int(named[2]),
            let hour = Int(named[3]),
            let minute = Int(named[4])
        else {
            return nil
        }

        return MailTimestamp(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
    }

    private static func captures(pattern: String, in value: String) -> [String]? {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: .caseInsensitive
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            )
        else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else {
                return nil
            }
            return String(value[range])
        }
    }

    private static func monthNumber(_ value: String) -> Int? {
        let months = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
        ]
        let normalized = value.lowercased()
        return months.firstIndex(where: { $0.hasPrefix(normalized) }).map { $0 + 1 }
    }
}

enum MailWindowIdentifier {
    private static let prefix = "Mail.messageViewer.window."

    static func viewerID(from identifier: String) -> Int? {
        guard identifier.hasPrefix(prefix) else {
            return nil
        }
        return Int(identifier.dropFirst(prefix.count))
    }
}

enum ResolvedMailMessageError: LocalizedError {
    case invalidWindowTitle
    case invalidMailboxLabel

    var errorDescription: String? {
        switch self {
        case .invalidWindowTitle:
            return "MailReveal could not read the linked message’s account."
        case .invalidMailboxLabel:
            return "MailReveal could not read the linked message’s mailbox."
        }
    }
}
