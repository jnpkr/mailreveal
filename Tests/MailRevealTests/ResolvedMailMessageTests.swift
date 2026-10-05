import Testing
@testable import MailReveal

@Suite("Resolved Mail message metadata")
struct ResolvedMailMessageTests {
    @Test("Parses Mail's account and mailbox labels")
    func parsesResolvedMessage() throws {
        let message = try ResolvedMailMessage(
            windowTitle: "Re: Link building – Work",
            mailboxLabel: " \u{fffc}Archive - Work",
            sender: "Example Sender <sender@example.test>",
            timestamp: "15 January 2024 at 13:47"
        )

        #expect(message.subject == "Re: Link building")
        #expect(message.accountName == "Work")
        #expect(message.mailboxName == "Archive")
        #expect(message.sender == "Example Sender <sender@example.test>")
        #expect(message.timestamp == "15 January 2024 at 13:47")
    }

    @Test("Uses the final separator when the subject contains a dash")
    func subjectContainsDash() throws {
        let message = try ResolvedMailMessage(
            windowTitle: "Status – September – Work - EU",
            mailboxLabel: "Archive - Work - EU",
            sender: "Sender",
            timestamp: "Today"
        )

        #expect(message.subject == "Status – September")
        #expect(message.accountName == "Work - EU")
        #expect(message.mailboxName == "Archive")
    }

    @Test("Rejects labels without an account separator")
    func invalidWindowTitle() {
        #expect(throws: ResolvedMailMessageError.self) {
            _ = try ResolvedMailMessage(
                windowTitle: "Message",
                mailboxLabel: "Inbox",
                sender: "Sender",
                timestamp: "Today"
            )
        }
    }
}

@Suite("Mail conversation subjects")
struct MailSubjectTests {
    @Test(
        "Removes reply and forward prefixes",
        arguments: [
            ("Re: Link building", "link building"),
            ("Fwd: Re: Link building", "link building"),
            ("FW:   Re:   Link building", "link building"),
            ("Quarterly report", "quarterly report"),
        ]
    )
    func conversationTitle(input: String, expected: String) {
        #expect(MailSubject.conversationTitle(input) == expected)
    }

    @Test(
        "Finds the conversation title in Mail's combined row label",
        arguments: [
            ("Link building", "Re: Link building", true),
            ("Re: Link building", "Re: Link building", true),
            ("  LINK   BUILDING ", "Fwd: Re: Link building", true),
            ("Work Archive - Work 15/01/2024 Re: Link building 81 KB", "Re: Link building", true),
            ("LLM SEO analysis", "Re: LLM SEO analysis", true),
            ("LLM analysis", "Re: LLM SEO analysis", false),
        ]
    )
    func rowTitle(rowLabel: String, subject: String, expected: Bool) {
        #expect(MailSubject.rowLabel(rowLabel, matches: subject) == expected)
    }
}

@Suite("Mail timestamps")
struct MailTimestampTests {
    @Test("Matches Mail's long resolver timestamp to its numeric conversation timestamp")
    func longAndNumericDates() {
        #expect(
            MailTimestamp.matches(
                "15 January 2024 at 13:47",
                in: "Archive - Work 15/01/2024 at 13:47"
            )
        )
        #expect(
            !MailTimestamp.matches(
                "15 January 2024 at 13:47",
                in: "Archive - Work 15/01/2024 at 13:48"
            )
        )
    }

    @Test("Matches relative timestamps without parsing them")
    func relativeDates() {
        #expect(
            MailTimestamp.matches(
                "Yesterday at 22:53",
                in: "Inbox - Personal Yesterday at 22:53"
            )
        )
    }
}
