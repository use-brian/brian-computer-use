import XCTest
@testable import BrianCore

final class MailSearchSessionTests: XCTestCase {
    let plan = MailSearchPlan(topics: ["flight"], date: "2026-11-16", dateScope: "event", dateVariants: ["Nov 16", "November 16"], queries: ["flight Nov 16", "flight November 16", "flight"])
    func testUndatedPlanRejectsDateFiltersInventedLater() {
        let plan = MailSearchPlan(topics: ["invoice", "AOGB"], queries: ["invoice AOGB", "AOGB"])
        var session = MailSearchSession(plan: plan)
        session.searched("invoice AOGB")
        XCTAssertEqual(session.correctedQuery("invoice November 16"), "AOGB")
        XCTAssertEqual(session.correctedQuery("invoice 2026-11-16"), "AOGB")
        XCTAssertEqual(session.correctedQuery("invoice 16 Nov"), "AOGB")
        XCTAssertEqual(session.correctedQuery("invoice tomorrow"), "AOGB")
    }
    func testRelativeWordsAndCaseVariantsCannotRepeatSearch() {
        var session = MailSearchSession(plan: plan)
        XCTAssertEqual(session.correctedQuery("flights tmr"), "flight Nov 16")
        session.searched("flight Nov 16")
        XCTAssertEqual(session.correctedQuery(" FLIGHT  nov 16 "), "flight November 16")
        XCTAssertEqual(session.correctedQuery("itinerary"), "itinerary", "A new model-chosen strategy remains available")
    }
    func testOnlyCurrentConfirmedEmptySearchTriggersAutomaticRetry() {
        var session = MailSearchSession(plan: plan); session.searched("flight Nov 16")
        let field = DesktopElement(id: "e0", role: "AXTextField", label: "Search", value: "flight Nov 16", enabled: true, editable: true, actions: [])
        let text = DesktopElement(id: "e1", role: "AXStaticText", label: "No Results", value: "", enabled: true, editable: false, actions: [])
        session.observe(.init(app: "com.apple.mail", name: "Mail", window: "Searching", accessibility: true, truncated: false, elements: [field, text]))
        XCTAssertFalse(session.lastWasEmpty)
        XCTAssertTrue(session.needsEmptyConfirmation)
        session.observe(.init(app: "com.apple.mail", name: "Mail", window: "Searching", accessibility: true, truncated: false, elements: [field, text]))
        XCTAssertTrue(session.lastWasEmpty)
        XCTAssertEqual(session.nextQuery, "flight November 16")
        session.searched("flight November 16")
        session.observe(.init(app: "com.apple.mail", name: "Mail", window: "Searching", accessibility: true, truncated: false, elements: [field, text]))
        XCTAssertFalse(session.lastWasEmpty, "Stale results for an older query cannot prove the next query empty")
    }
    func testSearchBudgetIncludesNovelModelQueries() {
        var session = MailSearchSession(plan: plan)
        for i in 0..<14 { session.searched("novel query \(i)") }
        XCTAssertNil(session.nextQuery)
        XCTAssertNil(session.correctedQuery("flights tomorrow"))
        XCTAssertNil(session.correctedQuery("another query"))
    }
    func testLiteralPhraseSearchRetainsRelativeWords() {
        let exact = MailSearchPlan(topics: ["flights tomorrow"], queries: ["flights tomorrow"], literal: true)
        XCTAssertEqual(MailSearchSession(plan: exact).correctedQuery("flights tomorrow"), "flights tomorrow")
    }
}
