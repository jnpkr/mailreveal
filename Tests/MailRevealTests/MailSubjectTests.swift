import Testing
@testable import MailReveal

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
