import XCTest
@testable import BrianCore

final class AutomaticTargetingTests: XCTestCase {
    func testChoosesSoleWindowWithoutManualSelection() {
        XCTAssertEqual(AutomaticTargeting.chooseWindow([.init(id: "document")]), "document")
    }
    func testFocusedWindowWinsOverMainAndEnumerationOrder() {
        XCTAssertEqual(AutomaticTargeting.chooseWindow([
            .init(id: "old", main: true), .init(id: "current", focused: true)]), "current")
        XCTAssertEqual(AutomaticTargeting.chooseWindow([
            .init(id: "other"), .init(id: "main", main: true)]), "main")
    }
    func testAmbiguousAndMissingWindowsNeverChooseArbitrarily() {
        XCTAssertNil(AutomaticTargeting.chooseWindow([]))
        XCTAssertNil(AutomaticTargeting.chooseWindow([.init(id: "a"), .init(id: "b")]))
        XCTAssertNil(AutomaticTargeting.chooseWindow([
            .init(id: "a", focused: true), .init(id: "b", focused: true)]))
    }
    func testExplicitAppAndEmailDestinationOverridePreviousContext() {
        XCTAssertEqual(AutomaticTargeting.destination(for: .init(kind: "open_app", app: "any.installed.app"), currentApp: "old.app"), "any.installed.app")
        XCTAssertEqual(AutomaticTargeting.destination(for: .init(kind: "search_mail", value: "AOGB invoice"), currentApp: "com.apple.calculator"), "com.apple.mail")
        XCTAssertEqual(AutomaticTargeting.destination(for: .init(kind: "read", target: "e1"), currentApp: "chosen.app"), "chosen.app")
    }
    func testOnlyForegroundDependentActionsRequireHandoff() {
        for action in [PlannerAction(kind: "press", target: "e1"), .init(kind: "search_mail", value: "invoice"),
                       .init(kind: "key", value: "cmd+f"), .init(kind: "key", value: "return")] {
            XCTAssertFalse(AutomaticTargeting.needsForeground(action))
        }
        for action in [PlannerAction(kind: "key", value: "cmd+v"), .init(kind: "key", value: "cmd+n"),
                       .init(kind: "vision_scroll", target: "capture", value: "500,500", message: "down")] {
            XCTAssertTrue(AutomaticTargeting.needsForeground(action))
        }
    }
}
