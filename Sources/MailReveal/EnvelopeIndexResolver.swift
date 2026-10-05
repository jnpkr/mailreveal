import Foundation

struct IndexedMailMessage: Equatable, Decodable {
    let libraryID: Int
    let messageID: String
    let mailboxURL: String
    let subject: String
    let sender: String
    let received: Date?

    var mailboxLocation: MailboxLocation? {
        MailboxLocation(url: mailboxURL)
    }

    private enum CodingKeys: String, CodingKey {
        case libraryID
        case messageID
        case mailboxURL
        case subject
        case sender
        case receivedTimestamp
    }

    init(
        libraryID: Int,
        messageID: String,
        mailboxURL: String,
        subject: String,
        sender: String,
        received: Date?
    ) {
        self.libraryID = libraryID
        self.messageID = messageID
        self.mailboxURL = mailboxURL
        self.subject = subject
        self.sender = sender
        self.received = received
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        libraryID = try values.decode(Int.self, forKey: .libraryID)
        messageID = try values.decode(String.self, forKey: .messageID)
        mailboxURL = try values.decode(String.self, forKey: .mailboxURL)
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        sender = try values.decodeIfPresent(String.self, forKey: .sender) ?? ""
        if let timestamp = try values.decodeIfPresent(Double.self, forKey: .receivedTimestamp),
           timestamp > 0 {
            received = Date(timeIntervalSince1970: timestamp)
        } else {
            received = nil
        }
    }
}

struct MailboxLocation: Equatable {
    let scheme: String
    let accountID: String
    let path: String

    init?(url: String) {
        guard
            let separator = url.range(of: "://"),
            !url[..<separator.lowerBound].isEmpty
        else {
            return nil
        }

        let remainder = url[separator.upperBound...]
        guard let slash = remainder.firstIndex(of: "/") else {
            return nil
        }

        let accountID = String(remainder[..<slash])
        let encodedPath = String(remainder[remainder.index(after: slash)...])
        guard !accountID.isEmpty, !encodedPath.isEmpty else {
            return nil
        }

        self.scheme = String(url[..<separator.lowerBound]).lowercased()
        self.accountID = accountID
        self.path = encodedPath.removingPercentEncoding ?? encodedPath
    }
}

final class EnvelopeIndexResolver {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let sqliteURL: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        sqliteURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.sqliteURL = sqliteURL
    }

    func resolve(messageID: String) throws -> IndexedMailMessage {
        let databaseURL = try envelopeIndexURL()
        let escapedID = Self.escapeSQL(messageID)
        let query = """
        SELECT
          m.ROWID AS libraryID,
          trim(mgd.message_id_header, '<>') AS messageID,
          mb.url AS mailboxURL,
          COALESCE(s.subject, '') AS subject,
          COALESCE(a.comment, a.address, '') AS sender,
          m.date_received AS receivedTimestamp
        FROM messages m
        JOIN message_global_data mgd ON m.global_message_id = mgd.ROWID
        LEFT JOIN mailboxes mb ON m.mailbox = mb.ROWID
        LEFT JOIN subjects s ON m.subject = s.ROWID
        LEFT JOIN addresses a ON m.sender = a.ROWID
        WHERE m.deleted = 0
          AND lower(trim(mgd.message_id_header, '<>')) = lower('\(escapedID)')
        ORDER BY m.date_received DESC, m.ROWID DESC
        LIMIT 20;
        """

        let data = try runSQLite(databaseURL: databaseURL, query: query)
        let matches = try JSONDecoder().decode([IndexedMailMessage].self, from: data)
        guard let match = Self.preferredMatch(among: matches) else {
            throw EnvelopeIndexError.messageNotFound
        }
        guard match.mailboxLocation != nil else {
            throw EnvelopeIndexError.invalidMailboxURL(match.mailboxURL)
        }
        return match
    }

    /// Chooses one copy when a message is stored in several mailboxes, as with
    /// Gmail labels alongside All Mail, or a message sent to oneself. A copy in an
    /// ordinary mailbox wins over All Mail, which wins over Trash and Junk. Ties
    /// keep the query order, newest first.
    static func preferredMatch(among matches: [IndexedMailMessage]) -> IndexedMailMessage? {
        matches.enumerated().min { lhs, rhs in
            (rank(lhs.element), lhs.offset) < (rank(rhs.element), rhs.offset)
        }?.element
    }

    private static func rank(_ message: IndexedMailMessage) -> Int {
        guard let location = message.mailboxLocation else {
            return 3
        }
        // Mailbox names are matched in English only; other names rank as ordinary.
        let leafName = location.path
            .split(separator: "/")
            .last
            .map { $0.lowercased() } ?? ""
        switch leafName {
        case "all mail":
            return 1
        case "trash", "bin", "deleted messages", "junk", "spam":
            return 2
        default:
            return 0
        }
    }

    private func envelopeIndexURL() throws -> URL {
        let mailURL = homeDirectory.appendingPathComponent("Library/Mail", isDirectory: true)
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: mailURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw EnvelopeIndexError.mailDataUnavailable(error.localizedDescription)
        }

        let versions = contents.compactMap { url -> (number: Int, url: URL)? in
            let name = url.lastPathComponent
            guard name.first == "V", let number = Int(name.dropFirst()) else { return nil }
            return (number, url)
        }.sorted { $0.number > $1.number }

        for version in versions {
            let candidate = version.url.appendingPathComponent("MailData/Envelope Index")
            if fileManager.isReadableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw EnvelopeIndexError.envelopeIndexNotFound
    }

    private func runSQLite(databaseURL: URL, query: String) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = sqliteURL
        process.arguments = ["-readonly", "-json", databaseURL.path, query]
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw EnvelopeIndexError.sqliteFailure(error.localizedDescription)
        }
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"
            throw EnvelopeIndexError.sqliteFailure(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outputData.isEmpty ? Data("[]".utf8) : outputData
    }

    static func escapeSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

enum EnvelopeIndexError: LocalizedError {
    case mailDataUnavailable(String)
    case envelopeIndexNotFound
    case unsupportedSchema([String])
    case sqliteFailure(String)
    case messageNotFound
    case invalidMailboxURL(String)

    var diagnosticCode: String {
        switch self {
        case .mailDataUnavailable: "mail-data-unavailable"
        case .envelopeIndexNotFound: "envelope-index-not-found"
        case .unsupportedSchema: "unsupported-index-schema"
        case .sqliteFailure: "sqlite-failure"
        case .messageNotFound: "message-not-found"
        case .invalidMailboxURL: "invalid-mailbox-url"
        }
    }

    var errorDescription: String? {
        switch self {
        case let .mailDataUnavailable(message):
            return "MailReveal could not read Mail’s local index: \(message)"
        case .envelopeIndexNotFound:
            return "MailReveal could not find Mail’s Envelope Index."
        case let .unsupportedSchema(columns):
            return "MailReveal does not recognise this Mail index schema (messages columns: \(columns.joined(separator: ", ")))."
        case let .sqliteFailure(message):
            return "MailReveal could not query Mail’s local index: \(message)"
        case .messageNotFound:
            return "MailReveal could not find this Message-ID in Mail’s local index."
        case let .invalidMailboxURL(url):
            return "MailReveal could not understand the indexed mailbox location: \(url)"
        }
    }
}
