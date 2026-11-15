import Foundation
import XCTest
@testable import BrianCore

final class InstructionParserTests: XCTestCase {
    func testOpensApplicationWithoutChangingItsName() throws {
        XCTAssertEqual(try InstructionParser().parse("  OPEN Google Chrome \n"), .openApplication("Google Chrome"))
        XCTAssertEqual(try InstructionParser().parse("launch Notes"), .openApplication("Notes"))
    }

    func testNormalizesWebAddresses() throws {
        XCTAssertEqual(try InstructionParser().parse("Open github.com/use-brian"), .openURL(URL(string: "https://github.com/use-brian")!))
        XCTAssertEqual(try InstructionParser().parse("https://example.com"), .openURL(URL(string: "https://example.com")!))
        XCTAssertEqual(try InstructionParser().parse("go to http://localhost:8080"), .openURL(URL(string: "http://localhost:8080")!))
    }

    func testKeepsSearchContentInOneQueryParameter() throws {
        let query = "coffee & tea + breakfast # nearby 日本語"
        let action = try InstructionParser().parse("Search for \(query)")
        XCTAssertEqual(action, .searchWeb(query))
        let url = try XCTUnwrap(action.webURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: query)])
        XCTAssertTrue(components.percentEncodedQuery?.contains("%2B") == true)
        XCTAssertNil(components.fragment)
    }

    func testRejectsEmptyInput() {
        for input in ["", " \n "] {
            XCTAssertThrowsError(try InstructionParser().parse(input)) {
                XCTAssertEqual($0 as? InstructionError, .empty)
            }
        }
    }

    func testRejectsUnsupportedInstructions() {
        for input in ["delete my downloads", "send an email", "search", "open"] {
            XCTAssertThrowsError(try InstructionParser().parse(input)) {
                XCTAssertEqual($0 as? InstructionError, .unsupported)
            }
        }
    }

    func testRejectsInvalidOrNonWebURLs() {
        for input in ["open file:///etc/passwd", "open javascript:alert(1)",
                      "open ftp://example.com", "open https://user:password@example.com",
                      "open https://", "open example.com bad", "go to Notes"] {
            XCTAssertThrowsError(try InstructionParser().parse(input), input) {
                XCTAssertEqual($0 as? InstructionError, .invalidURL, input)
            }
        }
    }
}
