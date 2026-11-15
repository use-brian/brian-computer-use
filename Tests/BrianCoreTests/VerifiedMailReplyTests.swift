import XCTest
@testable import BrianCore

final class VerifiedMailReplyTests: XCTestCase {
    func testDateCitationIncludesItsObservedItineraryContext() {
        let plan = MailSearchPlan(topics: ["flight"], date: "2026-11-16", dateScope: "event", dateVariants: ["16 Nov"], queries: ["flight Nov 16"])
        let content = "ExampleAir QX201\nMon 16 Nov 2026\nTPE 20:15"
        let parent = DesktopElement(id: "e0", role: "AXCell", label: "Itinerary", value: content, enabled: true, editable: false, actions: [], contentGroup: "e0")
        let date = DesktopElement(id: "e1", role: "AXStaticText", label: "", value: "Mon 16 Nov 2026", enabled: true, editable: false, actions: [], contentGroup: "e0")
        let snapshot = CompletionEvidence(id: "o1", observation: .init(app: "com.apple.mail", name: "Mail", window: "Confirmation", accessibility: true, truncated: false, elements: [parent, date]))
        let review = CompletionAssessment(complete: true, reason: "Date observed", checks: [.init(criterion: 0, satisfied: true, evidence: [.init(observation: "o1", element: "e1", quote: date.value)])])
        XCTAssertTrue(VerifiedMailReply.render(plan: plan, assessment: review, evidence: [snapshot])?.contains(content) == true)
        let bare = CompletionEvidence(id: "o1", observation: .init(app: "com.apple.mail", name: "Mail", window: "Confirmation", accessibility: true, truncated: false, elements: [date]))
        XCTAssertNil(VerifiedMailReply.render(plan: plan, assessment: review, evidence: [bare]))
    }
    func testDayOneDoesNotMatchDaySixteen() {
        let plan = MailSearchPlan(topics: ["flight"], date: "2026-11-01", dateScope: "event", dateVariants: ["Nov 1"], queries: ["flight Nov 1"])
        let row = DesktopElement(id: "e1", role: "AXCell", label: "Itinerary", value: "Departure Nov 16 2026 at 20:15", enabled: true, editable: false, actions: [])
        let snapshot = CompletionEvidence(id: "o1", observation: .init(app: "com.apple.mail", name: "Mail", window: "Confirmation", accessibility: true, truncated: false, elements: [row]))
        let review = CompletionAssessment(complete: true, reason: "Model claim", checks: [.init(criterion: 0, satisfied: true, evidence: [.init(observation: "o1", element: "e1", quote: row.value)])])
        XCTAssertNil(VerifiedMailReply.render(plan: plan, assessment: review, evidence: [snapshot]))
    }
    func testOnlyCitedContentWithRequestedYearAndDateCanBeReturned() {
        let plan = MailSearchPlan(topics: ["flight"], date: "2026-11-16", dateScope: "event", dateVariants: ["16 Nov"], queries: ["flight Nov 16"])
        let row = DesktopElement(id: "e1", role: "AXCell", label: "Itinerary", value: "Departure 16 Nov 2025 at 20:15", enabled: true, editable: false, actions: [])
        let snapshot = CompletionEvidence(id: "o1", observation: .init(app: "com.apple.mail", name: "Mail", window: "Confirmation", accessibility: true, truncated: false, elements: [row]))
        let review = CompletionAssessment(complete: true, reason: "Model claim", checks: [.init(criterion: 0, satisfied: true, evidence: [.init(observation: "o1", element: "e1", quote: row.value)])])
        XCTAssertNil(VerifiedMailReply.render(plan: plan, assessment: review, evidence: [snapshot]))
        XCTAssertNil(VerifiedMailReply.render(plan: plan, assessment: review, evidence: []))
        XCTAssertFalse(VerifiedMailReply.required(.init(topics: ["literal"], date: "2026-11-16", dateScope: "event", queries: ["literal"], literal: true)))
    }
}
