import Testing
@testable import MailReveal

@Suite("Mail viewer identifiers")
struct MailViewerIdentifierTests {
    @Test(
        "Parses only Mail viewer window identifiers",
        arguments: [
            ("Mail.messageViewer.window.3", 3),
            ("Mail.messageViewer.window.31", 31),
            ("Mail.messageViewer.window.", nil),
            ("Mail.compose.window.3", nil),
            ("Untitled", nil),
        ] as [(String, Int?)]
    )
    func viewerID(identifier: String, expected: Int?) {
        #expect(MailWindowIdentifier.viewerID(from: identifier) == expected)
    }
}
