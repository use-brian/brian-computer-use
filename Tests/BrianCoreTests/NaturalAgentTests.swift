import XCTest
import AppKit
@testable import BrianCore

private actor ScriptedPlanner: LanguagePlanner {
    var actions: [PlannerAction]
    var contexts: [JSONValue] = []
    var reviews: [JSONValue] = []
    var assessments: [CompletionAssessment]
    let mailPlan: MailSearchPlan?
    init(_ actions: [PlannerAction], assessments: [CompletionAssessment] = [], mailPlan: MailSearchPlan? = nil) { self.actions = actions; self.assessments = assessments; self.mailPlan = mailPlan }
    func goal(task: String, context: JSONValue) async throws -> TaskGoal {
        .init(objective: task, criteria: ["Requested outcome is visible"], mailSearch: mailPlan)
    }
    func assess(task: String, context: JSONValue) async throws -> CompletionAssessment {
        reviews.append(context)
        if !assessments.isEmpty { return assessments.removeFirst() }
        let current = context["current_observation_id"].string!
        let value = context["observation"]["elements"].array[0]["value"].string!
        return .init(complete: true, reason: "Verified fixture result", checks: [
            .init(criterion: 0, satisfied: true, evidence: [.init(observation: current, element: "e0", quote: value)])
        ])
    }
    func capturedReviews() -> [JSONValue] { reviews }
    func plan(task: String, context: JSONValue) async throws -> PlannerAction {
        contexts.append(context)
        guard !actions.isEmpty else { throw AgentError.invalidAction }
        return actions.removeFirst()
    }
    func captured() -> [JSONValue] { contexts }
}
@MainActor private final class FakeDesktop: DesktopTools {
    let applications = [DesktopApplication(id: "test.app", name: "Test")]
    var observed = 0
    var executed: [PlannerAction] = []
    var needsApproval = false
    var failExecution = false
    var recoverable = false
    var stableObservation = false
    var pendingVision: VisualSnapshot?
    var customObservation: DesktopObservation?
    func observe(app: String?) async throws -> DesktopObservation {
        observed += 1
        if let customObservation { return customObservation }
        let snapshot = pendingVision; pendingVision = nil
        return DesktopObservation(app: "test.app", name: "Test", window: "Window", accessibility: true, truncated: false,
            elements: [DesktopElement(id: "e0", role: "AXButton", label: "Button", value: stableObservation ? "unchanged" : String(executed.count), enabled: true, editable: false, actions: ["AXPress"])], vision: snapshot)
    }
    func confirmation(for action: PlannerAction, observation: DesktopObservation) -> String? { needsApproval ? "Proceed?" : nil }
    func execute(_ action: PlannerAction, observation: DesktopObservation) async throws -> DesktopToolResult {
        if recoverable && action.kind == "press" { throw DesktopRecoveryError.accessibilityUnavailable("No supported action; nothing dispatched") }
        if action.kind == "vision_observe" { pendingVision = .init(id: "capture-1", png: "synthetic") }
        if failExecution { throw AgentError.runtime("failed") }
        executed.append(action)
        return .init(app: "test.app", message: "Applied action \(executed.count)")
    }
}

@MainActor private final class AutomaticallyRoutedDesktop: DesktopTools {
    let applications = [DesktopApplication(id: "first.app", name: "First"), DesktopApplication(id: "second.app", name: "Second")]
    let planningInstructions = AutomaticTargeting.planningInstructions
    var current = "first.app"
    var executedApps: [String] = []
    func observe(app: String?) async throws -> DesktopObservation {
        .init(app: current, name: current, window: "Document", accessibility: true, truncated: false,
              elements: [.init(id: "e0", role: "AXButton", label: "Control", value: executedApps.isEmpty ? "Pending" : "Verified",
                               enabled: true, editable: false, actions: ["AXPress"])])
    }
    func confirmation(for action: PlannerAction, observation: DesktopObservation) -> String? { nil }
    func execute(_ action: PlannerAction, observation: DesktopObservation) async throws -> DesktopToolResult {
        if action.kind == "open_app" { current = action.app! }
        else { executedApps.append(current) }
        return .init(app: current, message: "Inspect the chosen app next.")
    }
}

@MainActor final class NaturalAgentTests: XCTestCase {
    func testAutomaticModeLetsPlannerChooseAnotherAppAndVerifyIt() async throws {
        let planner = ScriptedPlanner([.init(kind: "open_app", app: "second.app"),
                                       .init(kind: "press", target: "e0"), .init(kind: "done", message: "Verified")])
        let desktop = AutomaticallyRoutedDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Use the second app", app: "first.app",
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertFalse(result.needsInput)
        XCTAssertEqual(desktop.executedApps, ["second.app"])
        let contexts = await planner.captured()
        XCTAssertEqual(contexts[0]["scope_instructions"].string, AutomaticTargeting.planningInstructions)
        XCTAssertEqual(contexts[0]["installed_applications"].array.count, 2)
        XCTAssertEqual(contexts[1]["observation"]["app"].string, "second.app")
    }
    func testWindowScopeRejectsMailDetourBeforeExecution() async throws {
        let planner = ScriptedPlanner([.init(kind: "search_mail", value: "flight")])
        let desktop = FakeDesktop()
        do {
            _ = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find a flight email", app: "test.app", conversation: [],
                scope: .init(app: "test.app", title: "Selected"), approve: { _ in true }, onEvent: { _ in })
            XCTFail("A scoped task must not switch to Mail")
        } catch { XCTAssertTrue(desktop.executed.isEmpty) }
    }
    func testWindowScopeContextAndLocalActions() async throws {
        let planner = ScriptedPlanner([.init(kind: "press", target: "e0"), .init(kind: "done", message: "Verified")])
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Press this", app: "other.app", conversation: [],
            scope: .init(app: "test.app", title: "Selected"), approve: { _ in true }, onEvent: { _ in })
        XCTAssertFalse(result.needsInput)
        let contexts = await planner.captured()
        XCTAssertEqual(contexts[0]["execution_scope"]["app"].string, "test.app")
        XCTAssertEqual(contexts[0]["installed_applications"].array.count, 1)
    }
    func testDatedMailReplyUsesObservedExcerptInsteadOfInventedSummary() async throws {
        let text = "ExampleAir QX201 · Departure 16 Nov 2026 · TPE 20:15"
        let plan = MailSearchPlan(topics: ["flight"], date: "2026-11-16", dateScope: "event", dateVariants: ["16 Nov"], queries: ["flight Nov 16"])
        let planner = ScriptedPlanner([.init(kind: "done", message: "Invented return time 23:55 and cabin class")], mailPlan: plan)
        let desktop = FakeDesktop()
        desktop.customObservation = .init(app: "com.apple.mail", name: "Mail", window: "Confirmation", accessibility: true, truncated: false,
            elements: [.init(id: "e0", role: "AXCell", label: "Itinerary", value: text, enabled: true, editable: false, actions: [])])
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find my flight on 16 Nov", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertFalse(result.needsInput)
        XCTAssertTrue(result.message.contains(text))
        XCTAssertFalse(result.message.contains("23:55"))
        let reviews = await planner.capturedReviews()
        XCTAssertEqual(reviews.first?["reply_mode"].string, "excerpt")
    }
    func testRepeatedMailQueryIsNotExecutedAgainOrSentToVision() async throws {
        let planner = ScriptedPlanner(Array(repeating: .init(kind: "search_mail", value: "  Flight NOV 16  "), count: 4))
        let desktop = FakeDesktop(); desktop.stableObservation = true
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find tomorrow's flight email", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertTrue(result.needsInput)
        XCTAssertEqual(desktop.executed.map(\.kind), ["search_mail"])
        let contexts = await planner.captured()
        XCTAssertTrue(contexts[2]["completion_feedback"].string!.contains("already been tried"))
    }
    func testRepeatedMailQueryAdvancesToUntriedDateCombination() async throws {
        let plan = MailSearchPlan(topics: ["flight"], date: "2026-11-16", dateScope: "event", queries: ["flight Nov 16", "flight November 16", "itinerary 16 Nov"])
        let planner = ScriptedPlanner([.init(kind: "search_mail", value: "flight Nov 16"), .init(kind: "search_mail", value: "flight November 16"), .init(kind: "ask", message: "Need a sender")], mailPlan: plan)
        let desktop = FakeDesktop()
        _ = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find tomorrow's flight", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertEqual(desktop.executed.compactMap(\.value), plan.queries)
        XCTAssertFalse(desktop.executed.contains { $0.kind == "vision_observe" })
        let contexts = await planner.captured()
        XCTAssertEqual(contexts.last?["mail_search"]["attempts"].array.count, 3)
    }
    func testPlansAgainstFreshObservationsAndToolResults() async throws {
        let planner = ScriptedPlanner([.init(kind: "press", target: "e0"), .init(kind: "done", message: "Visible result")])
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Please do that for me", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(desktop.observed, 3, "Completion gets another fresh observation after planning")
        let contexts = await planner.captured()
        XCTAssertEqual(contexts[1]["history"].array.count, 1)
        XCTAssertEqual(contexts[1]["observation"]["elements"].array.first?["value"].string, "1")
    }
    func testFollowupContextAndClarificationArePassedToModel() async throws {
        let planner = ScriptedPlanner([.init(kind: "ask", message: "Which Sam?")])
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find his latest message", app: nil,
            conversation: [.init(role: "user", content: "I’m looking for Sam’s email")], approve: { _ in true }, onEvent: { _ in })
        XCTAssertTrue(result.needsInput)
        XCTAssertTrue(desktop.executed.isEmpty)
        let contexts = await planner.captured()
        XCTAssertEqual(contexts[0]["conversation"].array.count, 1)
    }
    func testDeclinedConfirmationNeverExecutes() async {
        let desktop = FakeDesktop(); desktop.needsApproval = true
        do {
            _ = try await NaturalAgent(planner: ScriptedPlanner([.init(kind: "press", target: "e0")]), tools: desktop)
                .run(task: "Proceed", app: nil, conversation: [], approve: { _ in false }, onEvent: { _ in })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(desktop.executed.isEmpty)
    }
    func testInvalidTargetCannotReachExecutor() async {
        let desktop = FakeDesktop()
        do {
            _ = try await NaturalAgent(planner: ScriptedPlanner([.init(kind: "press", target: "invented")]), tools: desktop)
                .run(task: "Click it", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
            XCTFail("Expected invalid target")
        } catch { XCTAssertEqual(error as? AgentError, .invalidAction) }
        XCTAssertTrue(desktop.executed.isEmpty)
    }
    func testExecutionErrorsAreNotRetried() async {
        let desktop = FakeDesktop(); desktop.failExecution = true
        let planner = ScriptedPlanner([.init(kind: "press", target: "e0")])
        do {
            _ = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Click it", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
            XCTFail("Expected failure")
        } catch {}
        let contexts = await planner.captured()
        XCTAssertEqual(contexts.count, 1)
    }
    func testRejectsShellURLsAndUninstalledApps() async throws {
        let desktop = FakeDesktop()
        let observation = try await desktop.observe(app: nil)
        for action in [PlannerAction(kind: "shell", value: "anything"), .init(kind: "open_url", value: "file:///tmp/script"), .init(kind: "open_app", app: "invented"), .init(kind: "key", value: "cmd+delete")] {
            XCTAssertThrowsError(try action.validate(observation: observation, apps: desktop.applications))
        }
    }
    func testActionBudgetStopsRun() async throws {
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: ScriptedPlanner([.init(kind: "press", target: "e0")]), tools: desktop, maxSteps: 1)
            .run(task: "Keep working", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertTrue(result.needsInput)
        XCTAssertEqual(desktop.executed.count, 1)
    }
    func testSafeCapabilityFailureUsesVisionThenReturnsToAccessibility() async throws {
        let desktop = FakeDesktop(); desktop.recoverable = true
        let planner = ScriptedPlanner([.init(kind: "press", target: "e0"),
            .init(kind: "vision_click", target: "capture-1", value: "600,400", message: "Continue"),
            .init(kind: "done", message: "Visible result")])
        _ = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Continue", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertEqual(desktop.executed.map(\.kind), ["vision_observe", "vision_click"])
        let contexts = await planner.captured()
        XCTAssertEqual(contexts[0]["observation"]["elements"].array.count, 1, "Accessibility is available from the first model turn")
        XCTAssertEqual(contexts[1]["observation"]["vision"]["id"].string, "capture-1")
        XCTAssertNil(contexts[2]["observation"]["vision"]["id"].string)
    }
    func testAlternatingAccessibilityCycleTriggersVision() async throws {
        let desktop = FakeDesktop(); desktop.stableObservation = true
        let planner = ScriptedPlanner([.init(kind: "open_app", app: "test.app"), .init(kind: "observe"),
            .init(kind: "open_app", app: "test.app"),
            .init(kind: "vision_click", target: "capture-1", value: "700,400", message: "Continue"), .init(kind: "done", message: "Visible result")])
        _ = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Continue", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertEqual(desktop.executed.map(\.kind), ["open_app", "observe", "vision_observe", "vision_click"])
    }
    func testPrematureSearchCompletionContinuesWithReviewerFeedback() async throws {
        let rejected = CompletionAssessment(complete: false, reason: "Read the result and verify its departure date", checks: [.init(criterion: 0, satisfied: false, evidence: [])])
        let planner = ScriptedPlanner([.init(kind: "search_mail", value: "flight"),
            .init(kind: "done", message: "Search is open"), .init(kind: "read", target: "e0"),
            .init(kind: "done", message: "Verified flight details")], assessments: [rejected])
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find my flights tomorrow in email", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertFalse(result.needsInput)
        XCTAssertEqual(desktop.executed.map(\.kind), ["search_mail", "read"])
        let contexts = await planner.captured()
        XCTAssertEqual(contexts[2]["completion_feedback"].string, rejected.reason)
        let reviews = await planner.capturedReviews()
        XCTAssertEqual(reviews.count, 2)
        XCTAssertGreaterThan(reviews[1]["evidence"].array.count, reviews[0]["evidence"].array.count)
    }
    func testRepeatedUnsupportedCompletionStopsAsIncomplete() async throws {
        let rejected = CompletionAssessment(complete: false, reason: "No departure date has been read", checks: [.init(criterion: 0, satisfied: false, evidence: [])])
        let planner = ScriptedPlanner([.init(kind: "search_mail", value: "flight"),
            .init(kind: "done", message: "Done"), .init(kind: "done", message: "Done"), .init(kind: "done", message: "Done")], assessments: [rejected, rejected, rejected])
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Find my flights tomorrow", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertTrue(result.needsInput)
        XCTAssertTrue(result.message.contains("couldn’t verify"))
        XCTAssertEqual(desktop.executed.count, 1)
    }
    func testForgedEvidenceCannotApproveCompletion() async throws {
        let forged = CompletionAssessment(complete: true, reason: "Looks done", checks: [.init(criterion: 0, satisfied: true,
            evidence: [.init(observation: "invented", element: "e0", quote: "flight tomorrow")])])
        let planner = ScriptedPlanner([.init(kind: "search_mail", value: "flight"), .init(kind: "done", message: "Found your flight"),
            .init(kind: "ask", message: "The flight date is not visible")], assessments: [forged])
        let result = try await NaturalAgent(planner: planner, tools: FakeDesktop()).run(task: "Find my flight tomorrow", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertTrue(result.needsInput)
        let contexts = await planner.captured()
        XCTAssertTrue(contexts.last!["completion_feedback"].string!.contains("invented evidence"))
    }
    func testEveryCriterionNeedsAnActualQuotedObservation() throws {
        let goal = TaskGoal(objective: "Both outcomes", criteria: ["First", "Second"])
        let evidence = [CompletionEvidence(id: "o1", observation: DesktopObservation(app: "test", name: "Test", window: "Saved document",
            accessibility: true, truncated: false, elements: []))]
        let cite = EvidenceCitation(observation: "o1", element: "window", quote: "Saved document")
        let missing = CompletionAssessment(complete: true, reason: "done", checks: [.init(criterion: 0, satisfied: true, evidence: [cite])])
        XCTAssertFalse(missing.accepts(goal: goal, evidence: evidence, currentID: "o1"))
        let bad = CompletionAssessment(complete: true, reason: "done", checks: [
            .init(criterion: 0, satisfied: true, evidence: [cite]),
            .init(criterion: 1, satisfied: true, evidence: [.init(observation: "o1", element: "window", quote: "Sent email")])])
        XCTAssertFalse(bad.accepts(goal: goal, evidence: evidence, currentID: "o1"))
    }
    func testSelectOnlyAcceptsObservedSelectableItems() throws {
        let row = DesktopElement(id: "e1", role: "AXRow", label: "Flight confirmation", value: "", enabled: true,
            editable: false, actions: [], selectable: true)
        let observation = DesktopObservation(app: "test", name: "Test", window: "Mail", accessibility: true, truncated: false, elements: [row])
        XCTAssertNoThrow(try PlannerAction(kind: "select", target: "e1").validate(observation: observation, apps: []))
        XCTAssertNoThrow(try PlannerAction(kind: "read", target: "e1").validate(observation: observation, apps: []))
        XCTAssertThrowsError(try PlannerAction(kind: "press", target: "e1").validate(observation: observation, apps: []))
        XCTAssertThrowsError(try PlannerAction(kind: "select", target: "missing").validate(observation: observation, apps: []))
    }
    func testPIDMouseEventsKeepWindowRelativeCoordinates() throws {
        let frame = CGRect(x: -800, y: 200, width: 800, height: 492)
        let point = CGPoint(x: -115, y: 596)
        for down in [true, false] {
            let cg = try XCTUnwrap(WindowPointerEvent.click(point: point, windowFrame: frame, windowNumber: 1234, down: down))
            let ns = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(ns.windowNumber, 1234)
            XCTAssertEqual(ns.locationInWindow.x, 685, accuracy: 0.01)
            XCTAssertEqual(ns.locationInWindow.y, 96, accuracy: 0.01)
            XCTAssertEqual(cg.getIntegerValueField(.mouseEventWindowUnderMousePointer), 1234)
        }
        XCTAssertNil(WindowPointerEvent.click(point: .zero, windowFrame: frame, windowNumber: 1234, down: true))
    }
    func testVisualFreshnessIgnoresDecorationButRejectsTargetOrPageChanges() throws {
        let before = [UInt8](repeating: 0, count: 128 * 128 * 4)
        var decoration = before
        for i in 0..<(128 * 8 * 4) { decoration[i] = 255 }
        let contentPoint = try VisualPoint("750,800")
        XCTAssertTrue(VisualFrameComparison.isUnchanged(before: before, after: decoration, point: contentPoint, chromeFraction: 0.08))
        XCTAssertFalse(VisualFrameComparison.isUnchanged(before: before, after: decoration, point: try VisualPoint("500,30"), chromeFraction: 0.08))
        var targetChange = before
        targetChange[(102 * 128 + 96) * 4] = 255
        XCTAssertFalse(VisualFrameComparison.isUnchanged(before: before, after: targetChange, point: contentPoint, chromeFraction: 0.08))
        var pageChange = before
        for i in (30 * 128 * 4)..<(34 * 128 * 4) { pageChange[i] = 255 }
        XCTAssertFalse(VisualFrameComparison.isUnchanged(before: before, after: pageChange, point: contentPoint, chromeFraction: 0.08))
    }
    func testVisualActionsRequireCurrentSnapshotAndBoundedCoordinates() async throws {
        let desktop = FakeDesktop()
        let noImage = try await desktop.observe(app: nil)
        let action = PlannerAction(kind: "vision_click", target: "capture-1", value: "500,500", message: "Continue")
        XCTAssertThrowsError(try action.validate(observation: noImage, apps: desktop.applications))
        desktop.pendingVision = .init(id: "capture-1", png: "synthetic")
        let image = try await desktop.observe(app: nil)
        XCTAssertNoThrow(try action.validate(observation: image, apps: desktop.applications))
        for value in ["NaN,500", "inf,500", "-1,500", "1000,500", "500", "500,500,500"] {
            XCTAssertThrowsError(try PlannerAction(kind: "vision_click", target: "capture-1", value: value, message: "Click").validate(observation: image, apps: desktop.applications))
        }
        XCTAssertThrowsError(try PlannerAction(kind: "vision_click", target: "old-capture", value: "500,500", message: "Click").validate(observation: image, apps: desktop.applications))
        let point = try VisualPoint("250,750")
        XCTAssertEqual(point.x, 0.25); XCTAssertEqual(point.y, 0.75)
    }
    func testCompletionWithoutAnyToolEvidenceIsRejected() async {
        do {
            _ = try await NaturalAgent(planner: ScriptedPlanner([.init(kind: "done", message: "I did it")]), tools: FakeDesktop())
                .run(task: "Find Cathay emails", app: nil, conversation: [], approve: { _ in true }, onEvent: { _ in })
            XCTFail("An initial completion claim must not bypass execution")
        } catch {}
    }
}
