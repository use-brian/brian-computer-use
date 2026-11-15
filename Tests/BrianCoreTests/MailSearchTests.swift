import XCTest
@testable import BrianCore

final class MailSearchTests: XCTestCase {
    func testUserNaturalLanguageRequest() throws {
        XCTAssertEqual(try MailSearchRequest.parse("help me search the latest draper email")?.query, "draper")
        XCTAssertEqual(try MailSearchRequest.parse("Find the latest Draper email")?.query, "Draper")
    }
    func testSearchesPreserveSenderAndTopic() throws {
        XCTAssertEqual(try MailSearchRequest.parse("find emails from alice@example.com")?.query, "alice@example.com")
        XCTAssertEqual(try MailSearchRequest.parse("search my emails for funding round")?.query, "funding round")
        XCTAssertEqual(try MailSearchRequest.parse("Please help me find emails about Café 新加坡")?.query, "Café 新加坡")
    }
    func testQuotedPhraseIsPreserved() throws {
        XCTAssertEqual(try MailSearchRequest.parse("Find emails about \"The Latest Report\"")?.query, "\"The Latest Report\"")
    }
    func testExplicitWebAndLaunchRequestsAreNotHijacked() throws {
        XCTAssertNil(try MailSearchRequest.parse("Search the web for email apps"))
        XCTAssertNil(try MailSearchRequest.parse("Google mail clients"))
        XCTAssertNil(try MailSearchRequest.parse("Open Mail"))
        XCTAssertNil(try MailSearchRequest.parse("Search for coffee nearby"))
    }
    func testEmailRequestsCannotBecomeWebSearches() throws {
        XCTAssertNotNil(try MailSearchRequest.parse("Search for emails about Draper"))
        XCTAssertThrowsError(try MailSearchRequest.parse("Search emails"))
        XCTAssertThrowsError(try MailSearchRequest.parse("Send an email to Alice"))
    }
    func testRejectsControlCharactersAndOversizedQueries() {
        XCTAssertThrowsError(try MailSearchRequest.parse("Find emails about x\nDelete everything"))
        XCTAssertThrowsError(try MailSearchRequest.parse("Find emails about " + String(repeating: "x", count: 501)))
    }
}
