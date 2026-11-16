import AppKit
import ApplicationServices
import BrianCore
import OSLog

/// Opt-in adapter. Native Mail search/keys/vision are chosen before dispatch;
/// agent-desktop ref actions are never retried through the native backend.
@MainActor final class AgentDesktopController: DesktopTools {
    private let native: DesktopController
    private let window: SelectedWindow
    private let cli: AgentDesktopCLI
    private let stateRoot: URL
    private var windowID: String?
    private var processInstance: String?
    private var snapshot: AgentDesktopSnapshot?
    private var readRoot: String?
    private var nativeObservation: DesktopObservation?
    private var searched = false
    private var safeRecoveries = 0
    var applications: [DesktopApplication] { native.applications.filter { $0.id == window.app } }
    init(native: DesktopController, window: SelectedWindow) throws {
        self.native = native; self.window = window
        let resources = Bundle.main.resourceURL!.appendingPathComponent("agent-desktop")
        stateRoot = FileManager.default.temporaryDirectory.appendingPathComponent("brian-agent-desktop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        cli = .init(executable: resources.appendingPathComponent("agent-desktop"),
                    host: Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("brian-runtime-host"), stateRoot: stateRoot)
    }
    func finish() { try? FileManager.default.removeItem(at: stateRoot) }
    private func verifyWindow() async throws -> String {
        try window.validate()
        let envelope = try await cli.call(["list-windows", "--app", window.name, "--timeout-ms", "3000"])
        let inventory = try AgentDesktopCLI.checked(envelope).array
        let matches = inventory.filter { item in
            guard item["pid"].integer == Int(window.pid), item["minimized"] != .bool(true) else { return false }
            if let windowID { return item["id"].string == windowID && item["process_instance"].string == processInstance }
            guard let position = SelectedWindow.attribute(window.window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = SelectedWindow.attribute(window.window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return false }
            var point = CGPoint.zero, dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return false }
            func number(_ key: String) -> Double? {
                switch item["bounds"][key] { case .decimal(let value): return value; case .number(let value): return Double(value); default: return nil }
            }
            guard let x = number("x"), let y = number("y"), let width = number("width"), let height = number("height") else { return false }
            return abs(x - point.x) < 2 && abs(y - point.y) < 2 && abs(width - dimensions.width) < 2 && abs(height - dimensions.height) < 2
        }
        guard matches.count == 1, let id = matches[0]["id"].string, let instance = matches[0]["process_instance"].string else {
            throw AgentError.runtime("agent-desktop could not uniquely identify the selected window. No input was sent.")
        }
        windowID = id; processInstance = instance; return id
    }
    func observe(app: String?) async throws -> DesktopObservation {
        guard app == nil || app == window.app else { throw AgentError.invalidAction }
        let id = try await verifyWindow()
        if nativeObservation != nil {
            let result = try await native.observe(app: window.app)
            nativeObservation = result
            return result
        }
        let base = ["snapshot", "--app", window.app, "--window-id", id]
        let skeleton = try await cli.call(base + ["--skeleton", "--timeout-ms", "4000"])
        _ = try AgentDesktopCLI.checked(skeleton)
        var snapshots: [JSONValue] = []
        if let readRoot {
            let detail = try await cli.call(["snapshot", "--root", readRoot, "--max-depth", "18", "--timeout-ms", "10000"])
            _ = try AgentDesktopCLI.checked(detail)
            snapshots.append(detail); self.readRoot = nil
        }
        // Message/document panes before result tables and sidebars. A full tree
        // is bounded and may be partial; never interpret partial as empty.
        if searched {
            func contentRef(_ node: JSONValue) -> String? {
                if node["native_id"]["value"].string == "_MAIL_MESSAGE_CONTENT" { return node["ref_id"].string }
                return node["children"].array.compactMap(contentRef).first
            }
            if let ref = contentRef(skeleton["data"]["tree"]) {
                let detail = try await cli.call(["snapshot", "--root", ref, "--max-depth", "18", "--timeout-ms", "8000"])
                if detail["ok"].isTrue { snapshots.append(detail) }
                else { _ = try AgentDesktopCLI.checked(detail) }
            }
        }
        snapshots.append(skeleton)
        if searched {
            snapshots.append(try await cli.call(base + ["--max-depth", "12", "--timeout-ms", "6000"]))
        }
        let mapped = try AgentDesktopSnapshot(app: window.app, name: window.name, windowID: id, snapshots: snapshots)
        snapshot = mapped
        return mapped.observation
    }
    private func present(_ target: AgentDesktopSnapshot.Target?, label: String) async {
        // Cached snapshot coordinates can be offscreen or out of date after a scroll.
        native.showTarget(rect: nil, label: label)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid,
              let ref = target?.ref ?? target?.readRoot,
              let result = try? await cli.call(["get", ref, "--property", "bounds"]),
              let bounds = AgentDesktopSnapshot.liveBounds(result),
              !Task.isCancelled else { return }
        native.showTarget(rect: bounds, label: label, cursor: true)
    }
    func confirmation(for action: PlannerAction, observation: DesktopObservation) -> String? {
        native.confirmation(for: action, observation: observation)
    }
    func execute(_ action: PlannerAction, observation: DesktopObservation) async throws -> DesktopToolResult {
        try window.scope.validate(action); try window.validate()
        try action.validate(observation: observation, apps: applications)
        _ = try await verifyWindow()
        if ["search_mail", "key", "vision_observe"].contains(action.kind) {
            let fresh = try await native.observe(app: window.app)
            let result = try await native.execute(action, observation: fresh)
            searched = searched || action.kind == "search_mail"
            if action.kind == "vision_observe" { nativeObservation = fresh }
            return result
        }
        if let nativeObservation {
            guard observation == nativeObservation else { throw AgentError.invalidAction }
            let result = try await native.execute(action, observation: observation)
            if !action.kind.hasPrefix("vision_") { self.nativeObservation = nil }
            return result
        }
        guard let snapshot, snapshot.observation == observation else { throw AgentError.invalidAction }
        switch action.kind {
        case "open_app", "observe": return .init(app: window.app, message: "The next observation stays in the selected window.")
        case "wait": try await Task.sleep(for: .milliseconds(700)); return .init(app: window.app, message: "Waited for the selected window.")
        case "read":
            guard let target = action.target, let binding = snapshot.targets[target] else { throw AgentError.invalidAction }
            await present(binding, label: "Reading content")
            readRoot = binding.readRoot; searched = true
            return .init(app: window.app, message: "Read this observed content and inspect its region on the next observation.")
        default:
            let binding = action.target.flatMap { snapshot.targets[$0] }
            let command = try AgentDesktopSnapshot.command(action, target: binding)
            await present(binding, label: action.activity(in: observation))
            try Task.checkCancellation()
            _ = try await verifyWindow()
            let result = try await cli.call(command.arguments + ["--timeout-ms", "5000"], input: command.input)
            do {
                _ = try AgentDesktopCLI.checked(result)
            } catch let failure as AgentDesktopFailure {
                // Metadata only; never record message bodies, field values or screenshots.
                Logger(subsystem: "com.usebrian.computer-use", category: "agent-desktop").error(
                    "Action \(action.kind, privacy: .public): \(failure.code, privacy: .public), operation \(failure.operation ?? "unknown", privacy: .public), delivery \(failure.delivery ?? "unknown", privacy: .public)")
                if !failure.safeToRetry, let ref = binding?.ref,
                   let prior = observation.elements.first(where: { $0.id == action.target }),
                   ["select", "set_text"].contains(action.kind) {
                    _ = try await verifyWindow()
                    let fresh = try? await cli.call(["snapshot", "--root", ref, "--max-depth", "2", "--timeout-ms", "4000"])
                    if let fresh, let windowID,
                       AgentDesktopSnapshot.verifies(action, prior: prior, rootSnapshot: fresh, windowID: windowID) {
                        searched = true
                        return .init(app: window.app, message: "The backend reported an error, but a fresh read of the exact target verified the requested selection/value. No action was repeated. Continue verifying the user's full request.")
                    }
                }
                if failure.safeToRetry, safeRecoveries < 2,
                   ["ACTION_FAILED", "STALE_REF", "AMBIGUOUS_TARGET", "TIMEOUT"].contains(failure.code) {
                    safeRecoveries += 1
                    if failure.code == "ACTION_FAILED" {
                        throw DesktopRecoveryError.accessibilityUnavailable("The headless control rejected this action before delivering any input. Inspect the selected window visually for another supported target.")
                    }
                    return .init(app: window.app, message: "The target could not be resolved; no input was delivered. Inspect a fresh observation before choosing the next action. " + failure.code)
                }
                throw AgentError.runtime("I couldn’t verify the \(action.kind == "select" ? "selection" : "action") in \(window.name). " +
                    (failure.operation == "AXSelected" ? "The app rejected selecting that item. " : "") +
                    "I stopped to avoid repeating an action that may already have applied.")
            }
            // A successful dispatch is never proof of completing the user's goal.
            searched = true
            return .init(app: window.app, message: "agent-desktop dispatched a headless action. Verify the effect in a fresh observation; do not repeat it through another backend.")
        }
    }
}
