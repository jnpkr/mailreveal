import Foundation

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

enum MailWindowIdentifier {
    private static let prefix = "Mail.messageViewer.window."

    static func viewerID(from identifier: String) -> Int? {
        guard identifier.hasPrefix(prefix) else {
            return nil
        }
        return Int(identifier.dropFirst(prefix.count))
    }
}
