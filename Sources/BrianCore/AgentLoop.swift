import Foundation

/// A bounded observe → infer → execute → re-observe loop. A policy stop is never
/// interpreted as proof that an arbitrary task succeeded.
public struct AgentLoop: Sendable {
    public let backend: any AgentBackend
    public var maxSteps = 12
    public var settleMilliseconds = 300

    public init(backend: any AgentBackend, maxSteps: Int = 12, settleMilliseconds: Int = 300) {
        self.backend = backend
        self.maxSteps = maxSteps
        self.settleMilliseconds = settleMilliseconds
    }

    public func run(task: String, app: AgentApp,
                    onEvent: @escaping @Sendable (AgentEvent) async -> Void) async throws -> AgentOutcome {
        let instruction = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, instruction.count <= 12000 else { throw AgentError.invalidTask }
        try Task.checkCancellation()
        await onEvent(.init(step: 0, message: "Checking the local model and app access…"))
        let status = try await backend.status()
        guard status.model_available, status.adapter_available else { throw AgentError.missingModel }
        guard status.native.accessibility_trusted else { throw AgentError.accessibility }

        var observation = try await backend.observe(app: app)
        let pid = observation.snapshot.pid
        let replacement = try Self.literalReplacement(instruction)
        // Exact text replacement is pinned to a single main document. Other
        // instructions retain app scope so the policy can reach the menu bar.
        let window = try replacement.map { _ in try Self.documentWindow(observation.snapshot) }
        var seen: [AXSnapshot] = []
        var executed = 0
        var lastAction: PolicyAction?
        var lastElement: AXElement?

        while true {
            try Task.checkCancellation()
            let snapshot = observation.snapshot
            guard snapshot.app == app.bundleIdentifier, snapshot.pid == pid else { throw AgentError.changedApp }
            guard !snapshot.truncated else { throw AgentError.truncated }
            if let window {
                guard snapshot.elements.contains(where: { $0.id == window.id && $0.role == window.role && $0.label == window.label }) else {
                    throw AgentError.lostWindow
                }
                let fields = snapshot.elements.filter {
                    $0.id.hasPrefix(window.id + ".") && $0.role == "AXTextArea" && $0.settable_value
                }
                if let replacement, fields.count == 1, fields[0].value == replacement {
                    return .verified("Verified: the selected document contains exactly the requested text.", steps: executed)
                }
            }
            if executed >= maxSteps {
                return .stopped("Reached the \(maxSteps)-action limit. Review the result before continuing.", steps: executed)
            }
            if seen.contains(snapshot) {
                return .stopped("The screen stopped changing or returned to an earlier state.", steps: executed)
            }
            seen.append(snapshot)
            await onEvent(.init(step: executed + 1, message: "Reading \(app.rawValue) and choosing the next action…"))
            let proposal = try await backend.propose(observation: observation, task: instruction, scopeID: window?.id ?? "")
            try Task.checkCancellation()
            try proposal.action.validate(in: snapshot)
            if proposal.action.action == "stop" {
                return .stopped("\(proposal.action.reason ?? "The model stopped.") Review the app; task completion is unverified.", steps: executed)
            }
            let element = snapshot.elements.first { $0.id == proposal.action.target }
            if proposal.action == lastAction, element?.label == lastElement?.label,
               element?.role == lastElement?.role {
                return .stopped("The model repeated its last action. Review the result before continuing.", steps: executed)
            }
            if let window, let target = proposal.action.target,
               !(target == window.id || target.hasPrefix(window.id + ".")) { throw AgentError.invalidAction }
            await onEvent(.init(step: executed + 1, message: proposal.action.summary(in: snapshot)))
            try Task.checkCancellation()
            // The runtime revalidates the exact snapshot and consumes the plan
            // token. Execution errors (including partial edits) are never retried.
            try await backend.execute(proposal: proposal)
            lastAction = proposal.action
            lastElement = element
            executed += 1
            try Task.checkCancellation()
            if settleMilliseconds > 0 { try await Task.sleep(for: .milliseconds(settleMilliseconds)) }
            await onEvent(.init(step: executed, message: "Checking the result in \(app.rawValue)…"))
            observation = try await backend.observe(app: app)
        }
    }

    private static func literalReplacement(_ task: String) throws -> String? {
        let prefix = "Replace the entire contents of the editable text area with exactly this text: "
        guard task.hasPrefix(prefix) else { return nil }
        guard let data = String(task.dropFirst(prefix.count)).data(using: .utf8),
              let text = try? JSONDecoder().decode(String.self, from: data) else { throw AgentError.invalidTask }
        return text
    }

    private static func documentWindow(_ snapshot: AXSnapshot) throws -> AXElement {
        let windows = snapshot.elements.filter { $0.role == "AXWindow" }
        let active = windows.filter { $0.main || $0.focused }
        if active.count == 1 { return active[0] }
        if windows.count == 1 { return windows[0] }
        throw AgentError.ambiguousWindow
    }
}
