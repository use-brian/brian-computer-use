import Foundation

public struct DesktopApplication: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct DesktopElement: Codable, Sendable, Equatable {
    public let id: String
    public let role: String
    public let label: String
    public let value: String
    public let enabled: Bool
    public let editable: Bool
    public let actions: [String]
    public init(id: String, role: String, label: String, value: String, enabled: Bool, editable: Bool, actions: [String]) {
        self.id = id; self.role = role; self.label = label; self.value = value
        self.enabled = enabled; self.editable = editable; self.actions = actions
    }
}
public struct VisualSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let png: String
    public init(id: String, png: String) { self.id = id; self.png = png }
}
/// Coordinates use the captured window, never the full desktop or device pixels.
public struct VisualPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public init(_ value: String) throws {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]),
              x.isFinite, y.isFinite, x > 0, x < 1000, y > 0, y < 1000 else { throw AgentError.invalidAction }
        self.x = x / 1000; self.y = y / 1000
    }
}
public struct DesktopObservation: Codable, Sendable, Equatable {
    public let app: String
    public let name: String
    public let window: String
    public let accessibility: Bool
    public let truncated: Bool
    public let elements: [DesktopElement]
    public let vision: VisualSnapshot?
    public init(app: String, name: String, window: String, accessibility: Bool, truncated: Bool, elements: [DesktopElement], vision: VisualSnapshot? = nil) {
        self.app = app; self.name = name; self.window = window
        self.accessibility = accessibility; self.truncated = truncated; self.elements = elements; self.vision = vision
    }
}
public struct PlannerAction: Codable, Sendable, Equatable {
    public let kind: String
    public let app: String?
    public let target: String?
    public let value: String?
    public let message: String?
    public init(kind: String, app: String? = nil, target: String? = nil, value: String? = nil, message: String? = nil) {
        self.kind = kind; self.app = app; self.target = target; self.value = value; self.message = message
    }
    public func validate(observation: DesktopObservation, apps: [DesktopApplication]) throws {
        let required: [String: Set<String>] = ["open_app":["app"], "open_url":["value"], "search_web":["value"],
            "search_mail":["value"], "press":["target"], "set_text":["target","value"], "key":["value"],
            "scroll":["target","value"], "wait":[], "observe":[], "ask":["message"], "done":["message"], "vision_observe":["message"],
            "vision_click":["target", "value", "message"], "vision_scroll":["target", "value", "message"]]
        var fields = Set<String>()
        if app != nil { fields.insert("app") }; if target != nil { fields.insert("target") }
        if value != nil { fields.insert("value") }; if message != nil { fields.insert("message") }
        guard let expected = required[kind], fields == expected,
              [app, target, value, message].compactMap({ $0 }).allSatisfy({ $0.count <= 8000 }) else { throw AgentError.invalidAction }
        if kind == "open_app" { guard apps.contains(where: { $0.id == app }) else { throw AgentError.invalidAction } }
        if kind == "open_url" {
            guard let value, let c = URLComponents(string: value), ["https", "http"].contains(c.scheme?.lowercased() ?? ""),
                  c.host?.isEmpty == false, c.user == nil, c.password == nil, c.url != nil else { throw AgentError.invalidAction }
        }
        if ["search_web", "search_mail", "key", "scroll"].contains(kind) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !value.contains(where: { $0.isNewline }) else { throw AgentError.invalidAction }
        }
        if kind == "key" { guard Self.keys.contains(value ?? "") else { throw AgentError.invalidAction } }
        if kind == "scroll" { guard ["up", "down"].contains(value ?? "") else { throw AgentError.invalidAction } }
        if ["ask", "done"].contains(kind) { guard message?.isEmpty == false else { throw AgentError.invalidAction } }
        if kind == "vision_observe" { guard message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw AgentError.invalidAction } }
        if kind.hasPrefix("vision_"), kind != "vision_observe" {
            guard let snapshot = observation.vision, target == snapshot.id,
                  let value, message?.isEmpty == false else { throw AgentError.invalidAction }
            _ = try VisualPoint(value)
            if kind == "vision_scroll", !["up", "down"].contains(message!) { throw AgentError.invalidAction }
            return
        }
        if let target {
            guard let e = observation.elements.first(where: { $0.id == target }), e.enabled else { throw AgentError.invalidAction }
            if kind == "press", Set(e.actions).isDisjoint(with: ["AXPress", "AXPick", "AXShowMenu"]) { throw AgentError.invalidAction }
            if kind == "set_text" {
                guard e.editable, ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(e.role),
                      let value, value.utf16.count <= 4000,
                      value.unicodeScalars.allSatisfy({ $0.value >= 32 || $0.value == 10 }),
                      e.role == "AXTextArea" || !value.contains("\n") else { throw AgentError.invalidAction }
            }
            if kind == "scroll", e.role != "AXScrollArea" { throw AgentError.invalidAction }
        }
    }
    public func activity(in observation: DesktopObservation) -> String {
        let name = observation.name.isEmpty ? "your app" : observation.name
        let label = observation.elements.first { $0.id == target }?.label
        switch kind {
        case "open_app": return "Opening the requested app…"
        case "open_url", "search_web": return "Opening your browser…"
        case "search_mail": return "Searching Mail…"
        case "vision_observe": return "Looking at \(name)…"
        case "vision_click": return "Clicking \(message ?? "the visual target")…"
        case "press": return "Clicking \(label?.isEmpty == false ? label! : "a control in " + name)…"
        case "set_text": return "Typing in \(name)…"
        case "scroll", "vision_scroll": return "Scrolling \(name)…"
        case "key": return "Using \(value ?? "a shortcut") in \(name)…"
        case "wait": return "Waiting for \(name)…"
        default: return "Reading \(name)…"
        }
    }
    public static let keys: Set<String> = ["return", "tab", "escape", "cmd+n", "cmd+f", "cmd+a", "cmd+c", "cmd+v", "cmd+z", "cmd+s", "left", "right", "up", "down"]
}

/// Only a capability check that proves no action was dispatched may trigger recovery.
public enum DesktopRecoveryError: Error { case accessibilityUnavailable(String) }

public protocol LanguagePlanner: Sendable {
    func plan(task: String, context: JSONValue) async throws -> PlannerAction
}
public struct DesktopToolResult: Sendable {
    public let app: String?
    public let message: String
    public init(app: String?, message: String) { self.app = app; self.message = message }
}
@MainActor public protocol DesktopTools {
    var applications: [DesktopApplication] { get }
    func observe(app: String?) async throws -> DesktopObservation
    func confirmation(for action: PlannerAction, observation: DesktopObservation) -> String?
    func execute(_ action: PlannerAction, observation: DesktopObservation) async throws -> DesktopToolResult
}
public struct ConversationTurn: Codable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = String(content.prefix(4000)) }
}
public struct NaturalResult: Sendable {
    public let message: String
    public let needsInput: Bool
    public let steps: Int
}

@MainActor public struct NaturalAgent {
    public let planner: any LanguagePlanner
    public let tools: any DesktopTools
    public var maxSteps: Int
    public init(planner: any LanguagePlanner, tools: any DesktopTools, maxSteps: Int = 16) {
        self.planner = planner; self.tools = tools; self.maxSteps = maxSteps
    }
    public func run(task: String, app: String?, conversation: [ConversationTurn],
                    approve: (String) async -> Bool,
                    onEvent: (String) -> Void) async throws -> NaturalResult {
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.count <= 12000 else { throw AgentError.invalidTask }
        var activeApp = app
        var history: [JSONValue] = []
        var attempts: [(PlannerAction, DesktopObservation)] = []
        var inspections = 0
        for step in 0..<maxSteps {
            try Task.checkCancellation()
            let observation = try await tools.observe(app: activeApp)
            let context: JSONValue = .object([
                "installed_applications": try json(tools.applications),
                "observation": try json(observation),
                "conversation": try json(Array(conversation.suffix(6))),
                "history": .array(history),
                "current_date": .string(ISO8601DateFormatter().string(from: Date())),
                "time_zone": .string(TimeZone.current.identifier),
            ])
            onEvent(step == 0 ? "Understanding your request…" : observation.vision != nil ? "Inspecting \(observation.name) visually…" : "Reading controls in \(observation.name)…")
            var action = try await planner.plan(task: task, context: context)
            try Task.checkCancellation()
            try action.validate(observation: observation, apps: tools.applications)
            if action.kind == "ask" || action.kind == "done" {
                guard action.kind != "done" || !history.isEmpty else { throw AgentError.runtime("The planner did not take an action. Please clarify your request.") }
                return NaturalResult(message: action.message!, needsInput: action.kind == "ask", steps: step)
            }
            let state = DesktopObservation(app: observation.app, name: observation.name, window: observation.window,
                accessibility: observation.accessibility, truncated: observation.truncated, elements: observation.elements)
            // Detect cycles as well as consecutive repeats. A fresh screenshot ID
            // or a reworded fallback reason is not evidence of task progress.
            let intent = PlannerAction(kind: action.kind, app: action.app, target: action.target,
                value: action.value, message: action.kind == "vision_observe" ? nil : action.message)
            let repeats = attempts.filter { $0.0 == intent && $0.1 == state }.count
            let inspectionOnly = ["observe", "wait"].contains(action.kind) || (action.kind == "open_app" && action.app == observation.app)
            inspections = inspectionOnly ? inspections + 1 : 0
            if repeats >= 2 || inspections > 2 {
                guard observation.vision == nil, !history.contains(where: { $0["action"]["kind"].string == "vision_observe" }) else {
                    return NaturalResult(message: "Neither Accessibility nor vision is making progress. Please review the app.", needsInput: true, steps: step)
                }
                action = .init(kind: "vision_observe", message: "Accessibility is cycling or repeatedly inspecting controls without acting. Inspect the visible window to find the missing target.")
                inspections = 0
            }
            attempts.append((intent, state))
            if let reason = tools.confirmation(for: action, observation: observation) {
                guard await approve(reason) else { throw CancellationError() }
                try Task.checkCancellation()
            }
            onEvent(action.activity(in: observation))
            let result: DesktopToolResult
            do {
                result = try await tools.execute(action, observation: observation)
            } catch DesktopRecoveryError.accessibilityUnavailable(let reason) {
                // Unknown failures/partial edits deliberately escape this catch.
                onEvent("Looking at \(observation.name)…")
                let fallback = PlannerAction(kind: "vision_observe", message: reason)
                result = try await tools.execute(fallback, observation: observation)
                history.append(.object(["action": try json(action), "result": .string("Accessibility unavailable before dispatch: " + reason)]))
                action = fallback
            }
            try Task.checkCancellation()
            activeApp = result.app ?? activeApp
            history.append(.object(["action": try json(action), "result": .string(String(result.message.prefix(1500)))]))
        }
        return NaturalResult(message: "I reached the action limit. Review the app before continuing.", needsInput: true, steps: maxSteps)
    }
    private func json<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}
