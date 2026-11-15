import XCTest
import AppKit
@testable import BrianCore

private actor ScriptedPlanner: LanguagePlanner {
    var actions: [PlannerAction]
    var contexts: [JSONValue] = []
    init(_ actions: [PlannerAction]) { self.actions = actions }
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
    func observe(app: String?) async throws -> DesktopObservation {
        observed += 1
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

@MainActor final class NaturalAgentTests: XCTestCase {
    func testPlansAgainstFreshObservationsAndToolResults() async throws {
        let planner = ScriptedPlanner([.init(kind: "press", target: "e0"), .init(kind: "done", message: "Visible result")])
        let desktop = FakeDesktop()
        let result = try await NaturalAgent(planner: planner, tools: desktop).run(task: "Please do that for me", app: nil,
            conversation: [], approve: { _ in true }, onEvent: { _ in })
        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(desktop.observed, 2)
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
