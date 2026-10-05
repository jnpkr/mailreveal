import Foundation
import Testing
@testable import MailReveal

@Suite("Message link parsing")
struct MessageLinkTests {
    @Test("Parses the standard encoded Mail URL")
    func standardEncodedURL() throws {
        let link = try MessageLink(url: #require(URL(string: "message://%3Cabc%40example.com%3E")))

        #expect(link.messageID == "abc@example.com")
        #expect(try link.mailURL.absoluteString == "message://%3Cabc%40example.com%3E")
    }

    @Test("Parses the single-slash form")
    func singleSlashURL() throws {
        let link = try MessageLink(url: #require(URL(string: "message:%3Cabc%40example.com%3E")))

        #expect(link.messageID == "abc@example.com")
    }

    @Test("Preserves a Message-ID without angle brackets")
    func unwrappedMessageID() throws {
        let link = try MessageLink(url: #require(URL(string: "message://abc%40example.com")))

        #expect(link.messageID == "abc@example.com")
    }

    @Test("Rejects another URL scheme")
    func wrongScheme() throws {
        #expect(throws: MessageLinkError.self) {
            _ = try MessageLink(url: #require(URL(string: "mailto:abc@example.com")))
        }
    }

    @Test("Rejects malformed and unsafe IDs", arguments: [
        "message://%3Cno-domain%3E",
        "message://%3Cabc%40example.com%3E?unexpected=true",
        "message://%3Cabc%0A%40example.com%3E",
    ])
    func malformedMessageID(rawURL: String) throws {
        #expect(throws: MessageLinkError.self) {
            _ = try MessageLink(url: #require(URL(string: rawURL)))
        }
    }
}
