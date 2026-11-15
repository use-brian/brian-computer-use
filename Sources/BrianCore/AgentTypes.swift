import Foundation

public enum AgentApp: String, CaseIterable, Codable, Sendable {
    case textEdit = "TextEdit", finder = "Finder"
    public var bundleIdentifier: String {
        self == .textEdit ? "com.apple.TextEdit" : "com.apple.finder"
    }
}

public struct AXElement: Codable, Equatable, Sendable {
    public let id: String
    public let role: String
    public let label: String
    public let value: String
    public let enabled: Bool
    public let actions: [String]
    public let settable_value: Bool
    public let focused: Bool
    public let main: Bool
}

public struct AXSnapshot: Codable, Equatable, Sendable {
    public let app: String
    public let pid: Int
    public let elements: [AXElement]
    public let truncated: Bool
}

public struct Observation: Codable, Sendable {
    public let snapshot_id: String
    public let snapshot: AXSnapshot
}

public struct PolicyAction: Codable, Equatable, Sendable {
    public let action: String
    public let target: String?
    public let value: String?
    public let reason: String?

    public func validate(in snapshot: AXSnapshot) throws {
        if action == "stop" {
            guard let reason, !reason.isEmpty, target == nil, value == nil else {
                throw AgentError.invalidAction
            }
            return
        }
        guard ["press", "set_value"].contains(action), reason == nil,
              let target, snapshot.elements.filter({ $0.id == target }).count == 1,
              let element = snapshot.elements.first(where: { $0.id == target }), element.enabled else {
            throw AgentError.invalidAction
        }
        if action == "press" {
            guard element.actions.contains("AXPress"), value == nil else { throw AgentError.invalidAction }
        } else {
            guard element.settable_value, ["AXTextArea", "AXTextField", "AXSearchField"].contains(element.role),
                  let value, value.utf16.count <= 2000, value.filter({ $0 == "\n" }).count <= 50,
                  value.unicodeScalars.allSatisfy({ $0.value >= 32 || $0.value == 10 }),
                  element.role == "AXTextArea" || !value.contains("\n") else { throw AgentError.invalidAction }
        }
    }

    public func summary(in snapshot: AXSnapshot) -> String {
        let element = snapshot.elements.first { $0.id == target }
        let label = element?.label.isEmpty == false ? element!.label : (element?.role ?? "control")
        switch action {
        case "press": return "Press \(label)"
        case "set_value": return "Replace text in \(label)"
        default: return reason ?? "Stop"
        }
    }
}

public struct Proposal: Codable, Sendable {
    public let plan_id: String
    public let action: PolicyAction
    public let decision: JSONValue?
    public let raw_model_output: String?
}

public struct RuntimeStatus: Codable, Sendable {
    public struct Native: Codable, Sendable { public let accessibility_trusted: Bool }
    public let native: Native
    public let model_available: Bool
    public let adapter_available: Bool
    public let model_loaded: Bool
}

public protocol AgentBackend: Sendable {
    func status() async throws -> RuntimeStatus
    func observe(app: AgentApp) async throws -> Observation
    func propose(observation: Observation, task: String, scopeID: String) async throws -> Proposal
    func execute(proposal: Proposal) async throws
    func shutdown() async
}

public enum AgentError: LocalizedError, Equatable {
    case missingRuntime, missingModel, accessibility, invalidAction, invalidTask
    case changedApp, ambiguousWindow, lostWindow, truncated
    case runtime(String)

    public var errorDescription: String? {
        switch self {
        case .missingRuntime: "The local model runtime is missing. Build Brian with the llm-research bundle."
        case .missingModel: "The bundled base model or trained adapter is missing. Rebuild the full app."
        case .accessibility: "Allow Brian in System Settings → Privacy & Security → Accessibility, then retry."
        case .invalidAction: "The model proposed an unsupported action. No further action was taken."
        case .invalidTask: "Enter an instruction of 1–12,000 characters."
        case .changedApp: "The target app restarted or changed. Submit the task again."
        case .ambiguousWindow: "Select the document you want in TextEdit, then try again."
        case .lostWindow: "The selected document changed or closed. Review it before continuing."
        case .truncated: "The app has too many controls to inspect completely. Close extra windows and retry."
        case .runtime(let message): message
        }
    }
}

public enum AgentOutcome: Equatable, Sendable {
    case verified(String, steps: Int)
    case stopped(String, steps: Int)
    public var message: String {
        switch self {
        case .verified(let message, _): message
        case .stopped(let reason, let steps): "Stopped after \(steps) action(s): \(reason)"
        }
    }
}

public struct AgentEvent: Sendable {
    public let step: Int
    public let message: String
}
