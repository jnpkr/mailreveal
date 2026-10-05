import Foundation

struct MessageLink: Equatable {
    let messageID: String

    init(url: URL) throws {
        let absoluteString = url.absoluteString
        guard let colonIndex = absoluteString.firstIndex(of: ":") else {
            throw MessageLinkError.invalidScheme
        }

        let scheme = absoluteString[..<colonIndex]
        guard scheme.caseInsensitiveCompare("message") == .orderedSame else {
            throw MessageLinkError.invalidScheme
        }

        var encodedPayload = String(absoluteString[absoluteString.index(after: colonIndex)...])
        if encodedPayload.hasPrefix("//") {
            encodedPayload.removeFirst(2)
        }

        guard
            !encodedPayload.isEmpty,
            !encodedPayload.contains("?"),
            !encodedPayload.contains("#"),
            let decodedPayload = encodedPayload.removingPercentEncoding
        else {
            throw MessageLinkError.invalidMessageID
        }

        var messageID = decodedPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        if messageID.hasPrefix("<"), messageID.hasSuffix(">") {
            messageID.removeFirst()
            messageID.removeLast()
        }

        let containsControlCharacter = messageID.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }

        guard
            !messageID.isEmpty,
            messageID.count <= 998,
            messageID.contains("@"),
            !messageID.contains("<"),
            !messageID.contains(">"),
            !containsControlCharacter
        else {
            throw MessageLinkError.invalidMessageID
        }

        self.messageID = messageID
    }

    var mailURL: URL {
        get throws {
            var allowedCharacters = CharacterSet.alphanumerics
            allowedCharacters.insert(charactersIn: "-._~")

            guard
                let encodedMessageID = "<\(messageID)>".addingPercentEncoding(
                    withAllowedCharacters: allowedCharacters
                ),
                let url = URL(string: "message://\(encodedMessageID)")
            else {
                throw MessageLinkError.invalidMessageID
            }

            return url
        }
    }
}

enum MessageLinkError: LocalizedError {
    case invalidScheme
    case invalidMessageID

    var diagnosticCode: String {
        switch self {
        case .invalidScheme: "invalid-scheme"
        case .invalidMessageID: "invalid-message-id"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "MailReveal only handles message: links."
        case .invalidMessageID:
            return "The link does not contain a valid RFC Message-ID."
        }
    }
}
