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
}
