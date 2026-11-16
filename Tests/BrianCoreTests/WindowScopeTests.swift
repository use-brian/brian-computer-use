import XCTest
@testable import BrianCore

final class WindowScopeTests: XCTestCase {
    func testWindowModeRejectsEscapesAndSharedInput() throws {
        let scope = WindowScope(app: "com.apple.mail", title: "Inbox")
        for action in [PlannerAction(kind: "open_app", app: "com.apple.Safari"),
                       .init(kind: "open_url", value: "https://example.com"), .init(kind: "search_web", value: "test"),
                       .init(kind: "key", value: "cmd+v"), .init(kind: "key", value: "cmd+c"), .init(kind: "key", value: "cmd+n"),
                       .init(kind: "vision_scroll", target: "image", value: "500,500", message: "down")] {
            XCTAssertThrowsError(try scope.validate(action))
        }
        XCTAssertThrowsError(try WindowScope(app: "com.apple.TextEdit", title: "Note").validate(.init(kind: "search_mail", value: "flight")))
    }
    func testWindowModeAllowsScopedOperations() throws {
        let scope = WindowScope(app: "com.apple.mail", title: "Inbox")
        for action in [PlannerAction(kind: "open_app", app: scope.app), .init(kind: "search_mail", value: "flight"),
                       .init(kind: "key", value: "return"), .init(kind: "read", target: "e1"),
                       .init(kind: "set_text", target: "e2", value: "test"), .init(kind: "press", target: "e3"),
                       .init(kind: "vision_observe", message: "Inspect the selected window")] { XCTAssertNoThrow(try scope.validate(action)) }
    }
}
