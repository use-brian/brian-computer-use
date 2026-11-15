import Foundation
import XCTest
@testable import BrianCore

final class AgentLoopTests: XCTestCase, @unchecked Sendable {
    func testObservesAgainBetweenEveryAction() async throws {
        let backend = FakeBackend(states: [state("A"), state("B"), state("C")],
                                  actions: [press(), PolicyAction(action: "set_value", target: "0.1.1", value: "C", reason: nil), stop()])
        let result = try await AgentLoop(backend: backend, settleMilliseconds: 0)
            .run(task: "Do a task", app: .textEdit) { _ in }
        guard case .stopped(_, steps: 2) = result else { return XCTFail("Unexpected outcome") }
        let calls = await backend.calls
        XCTAssertEqual(calls, ["status", "observe", "propose:0", "execute:0", "observe", "propose:1", "execute:1", "observe", "propose:2"])
    }

    func testStopsWithoutRepeatingAnUnchangedAction() async throws {
        let backend = FakeBackend(states: [state("A"), state("A")], actions: [press(), press()])
        let result = try await AgentLoop(backend: backend, settleMilliseconds: 0)
            .run(task: "Press Save", app: .textEdit) { _ in }
        guard case .stopped(let reason, steps: 1) = result else { return XCTFail("Unexpected outcome") }
        XCTAssertTrue(reason.contains("stopped changing"))
        let executions = await backend.executions
        XCTAssertEqual(executions, 1)
    }

    func testEnforcesActionBudget() async throws {
        let backend = FakeBackend(states: [state("A"), state("B")], actions: [press(), press()])
        let result = try await AgentLoop(backend: backend, maxSteps: 1, settleMilliseconds: 0)
            .run(task: "Do a task", app: .textEdit) { _ in }
        guard case .stopped(let reason, steps: 1) = result else { return XCTFail("Unexpected outcome") }
        XCTAssertTrue(reason.contains("limit"))
    }

    func testRepeatedActionIsNotExecutedEvenWhenFocusOrContentChanged() async throws {
        let backend = FakeBackend(states: [state("A"), state("B")], actions: [press(), press()])
        let result = try await AgentLoop(backend: backend, settleMilliseconds: 0)
            .run(task: "Press Save", app: .textEdit) { _ in }
        guard case .stopped(let reason, steps: 1) = result else { return XCTFail("Unexpected outcome") }
        XCTAssertTrue(reason.contains("repeated"))
        let count = await backend.executions
        XCTAssertEqual(count, 1)
    }

    func testVerifiesLiteralTextFromFreshReadback() async throws {
        let replacement = "Café 新加坡\n"
        let action = PolicyAction(action: "set_value", target: "0.1.1", value: replacement, reason: nil)
        let backend = FakeBackend(states: [state("old"), state(replacement)], actions: [action])
        let task = "Replace the entire contents of the editable text area with exactly this text: "
            + String(data: try JSONEncoder().encode(replacement), encoding: .utf8)!
        let result = try await AgentLoop(backend: backend, settleMilliseconds: 0)
            .run(task: task, app: .textEdit) { _ in }
        guard case .verified(_, steps: 1) = result else { return XCTFail("Must verify fresh text") }
        let scope = await backend.lastScope
        XCTAssertEqual(scope, "0.1")
    }

    func testModelStopIsNotSuccess() async throws {
        let backend = FakeBackend(states: [state("old")], actions: [stop("Task completed")])
        let result = try await AgentLoop(backend: backend).run(task: "Do a task", app: .textEdit) { _ in }
        guard case .stopped(let reason, steps: 0) = result else { return XCTFail("Must not trust a success claim") }
        XCTAssertTrue(reason.contains("unverified"))
    }

    func testRejectsUnknownTargetsBeforeExecution() async throws {
        let backend = FakeBackend(states: [state("old")], actions: [press("not-in-snapshot")])
        do {
            _ = try await AgentLoop(backend: backend).run(task: "Do a task", app: .textEdit) { _ in }
            XCTFail("Expected invalid action")
        } catch { XCTAssertEqual(error as? AgentError, .invalidAction) }
        let count = await backend.executions
        XCTAssertEqual(count, 0)
    }

    func testPermissionFailureDoesNotObserveOrExecute() async throws {
        let backend = FakeBackend(states: [state("old")], actions: [press()], trusted: false)
        do {
            _ = try await AgentLoop(backend: backend).run(task: "Do a task", app: .textEdit) { _ in }
            XCTFail("Expected permission error")
        } catch { XCTAssertEqual(error as? AgentError, .accessibility) }
        let calls = await backend.calls
        XCTAssertEqual(calls, ["status"])
    }

    func testExecutionFailureIsNeverRetried() async throws {
        let backend = FakeBackend(states: [state("old")], actions: [press()], failExecution: true)
        do {
            _ = try await AgentLoop(backend: backend).run(task: "Do a task", app: .textEdit) { _ in }
            XCTFail("Expected error")
        } catch { XCTAssertEqual(error as? AgentError, .runtime("partial edit")) }
        let count = await backend.executions
        XCTAssertEqual(count, 1)
    }

    func testCancellationAfterInferencePreventsExecution() async throws {
        let backend = FakeBackend(states: [state("old")], actions: [press()], slowProposal: true)
        let task = Task { try await AgentLoop(backend: backend).run(task: "Do a task", app: .textEdit) { _ in } }
        while !(await backend.proposing) { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await backend.executions
        XCTAssertEqual(count, 0)
    }

    func testRejectsTruncatedObservation() async throws {
        let initial = state("old")
        let snapshot = AXSnapshot(app: initial.app, pid: initial.pid, elements: initial.elements, truncated: true)
        let backend = FakeBackend(states: [snapshot], actions: [press()])
        do {
            _ = try await AgentLoop(backend: backend).run(task: "Do a task", app: .textEdit) { _ in }
            XCTFail("Expected truncated snapshot error")
        } catch { XCTAssertEqual(error as? AgentError, .truncated) }
    }
}

private func state(_ value: String) -> AXSnapshot {
    AXSnapshot(app: AgentApp.textEdit.bundleIdentifier, pid: 42, elements: [
        AXElement(id: "0.1", role: "AXWindow", label: "Disposable.txt", value: "", enabled: true, actions: [], settable_value: false, focused: false, main: true),
        AXElement(id: "0.1.1", role: "AXTextArea", label: "", value: value, enabled: true, actions: [], settable_value: true, focused: true, main: false),
        AXElement(id: "0.2", role: "AXButton", label: "Save", value: "", enabled: true, actions: ["AXPress"], settable_value: false, focused: false, main: false),
    ], truncated: false)
}
private func press(_ id: String = "0.2") -> PolicyAction { .init(action: "press", target: id, value: nil, reason: nil) }
private func stop(_ reason: String = "No further action") -> PolicyAction { .init(action: "stop", target: nil, value: nil, reason: reason) }

private actor FakeBackend: AgentBackend {
    let states: [AXSnapshot]
    let actions: [PolicyAction]
    let trusted: Bool
    let failExecution: Bool
    let slowProposal: Bool
    var index = 0
    var executions = 0
    var proposing = false
    var lastScope = ""
    var calls: [String] = []
    init(states: [AXSnapshot], actions: [PolicyAction], trusted: Bool = true, failExecution: Bool = false, slowProposal: Bool = false) {
        self.states = states; self.actions = actions; self.trusted = trusted
        self.failExecution = failExecution; self.slowProposal = slowProposal
    }
    func status() async throws -> RuntimeStatus {
        calls.append("status")
        return .init(native: .init(accessibility_trusted: trusted), model_available: true, adapter_available: true, model_loaded: true)
    }
    func observe(app: AgentApp) async throws -> Observation {
        calls.append("observe")
        return .init(snapshot_id: String(index), snapshot: states[min(index, states.count - 1)])
    }
    func propose(observation: Observation, task: String, scopeID: String) async throws -> Proposal {
        calls.append("propose:\(index)"); lastScope = scopeID; proposing = true
        if slowProposal { try await Task.sleep(for: .seconds(10)) }
        return .init(plan_id: String(index), action: actions[min(index, actions.count - 1)], decision: nil, raw_model_output: nil)
    }
    func execute(proposal: Proposal) async throws {
        calls.append("execute:\(index)"); executions += 1
        if failExecution { throw AgentError.runtime("partial edit") }
        index += 1
    }
    func shutdown() async {}
}
