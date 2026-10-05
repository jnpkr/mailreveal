import Foundation
import Testing
@testable import MailReveal

@Suite("Envelope Index resolution")
struct EnvelopeIndexResolverTests {
    @Test("Parses and decodes Mail mailbox URLs")
    func mailboxURL() {
        let location = MailboxLocation(url: "imap://ABC-123/%5BGmail%5D/All%20Mail")
        #expect(location?.scheme == "imap")
        #expect(location?.accountID == "ABC-123")
        #expect(location?.path == "[Gmail]/All Mail")
        #expect(MailboxLocation(url: "not-a-mailbox") == nil)
    }

    @Test("Escapes SQL text without changing other characters")
    func sqlEscaping() {
        #expect(EnvelopeIndexResolver.escapeSQL("one'two@example.com") == "one''two@example.com")
        #expect(EnvelopeIndexResolver.escapeSQL("a+b@example.com") == "a+b@example.com")
    }

    @Test("Decodes sqlite JSON rows")
    func rowDecoding() throws {
        let json = """
        [{"libraryID":42,"messageID":"abc@example.com","mailboxURL":"imap://A/INBOX","subject":"Hello","sender":"a@example.com","receivedTimestamp":1000}]
        """
        let result = try JSONDecoder().decode([IndexedMailMessage].self, from: Data(json.utf8))
        #expect(result == [
            IndexedMailMessage(
                libraryID: 42,
                messageID: "abc@example.com",
                mailboxURL: "imap://A/INBOX",
                subject: "Hello",
                sender: "a@example.com",
                received: Date(timeIntervalSince1970: 1000)
            ),
        ])
    }

    @Test("Prefers an ordinary mailbox over All Mail, Trash and Junk")
    func preferredMatch() {
        let trash = message(libraryID: 1, mailboxURL: "imap://A/%5BGmail%5D/Trash")
        let allMail = message(libraryID: 2, mailboxURL: "imap://A/%5BGmail%5D/All%20Mail")
        let label = message(libraryID: 3, mailboxURL: "imap://A/Projects/Client")
        let invalid = message(libraryID: 4, mailboxURL: "not-a-mailbox")

        #expect(EnvelopeIndexResolver.preferredMatch(among: [invalid, trash, allMail, label]) == label)
        #expect(EnvelopeIndexResolver.preferredMatch(among: [invalid, trash, allMail]) == allMail)
        #expect(EnvelopeIndexResolver.preferredMatch(among: [invalid, trash]) == trash)
        #expect(EnvelopeIndexResolver.preferredMatch(among: []) == nil)
    }

    @Test("Keeps the newest-first query order between equally ranked copies")
    func preferredMatchTie() {
        let inbox = message(libraryID: 1, mailboxURL: "imap://A/INBOX")
        let sent = message(libraryID: 2, mailboxURL: "imap://A/Sent")

        #expect(EnvelopeIndexResolver.preferredMatch(among: [inbox, sent]) == inbox)
        #expect(EnvelopeIndexResolver.preferredMatch(among: [sent, inbox]) == sent)
    }

    private func message(libraryID: Int, mailboxURL: String) -> IndexedMailMessage {
        IndexedMailMessage(
            libraryID: libraryID,
            messageID: "abc@example.com",
            mailboxURL: mailboxURL,
            subject: "Hello",
            sender: "a@example.com",
            received: nil
        )
    }
}
