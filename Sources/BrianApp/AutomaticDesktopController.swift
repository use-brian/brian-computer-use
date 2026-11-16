import AppKit
import ApplicationServices
import BrianCore

/// The planner chooses apps; the harness chooses and pins their real windows.
/// Backend choice is internal and happens before dispatch, never after an
/// uncertain input failure. The user does not need a target/backend picker.
@MainActor final class AutomaticDesktopController: DesktopTools {
    private let native: DesktopController
    private let onApp: (String) -> Void
    private var window: SelectedWindow?
    private var external: AgentDesktopController?
    private var lastObservation: DesktopObservation?
    private var foregroundRequest: PlannerAction?
    var applications: [DesktopApplication] { native.controllableApplications }
    var planningInstructions: String { AutomaticTargeting.planningInstructions }
    init(native: DesktopController, onApp: @escaping (String) -> Void) {
        self.native = native; self.onApp = onApp
    }
    func finish() {
        external?.finish(); external = nil
        native.finish(); native.bind(nil)
        window = nil; lastObservation = nil; foregroundRequest = nil
    }
    private func chooseApp(_ id: String, launch: Bool) async throws -> Bool {
        try Task.checkCancellation()
        guard applications.contains(where: { $0.id == id }) else { throw AgentError.invalidAction }
        if let window, window.app == id { try window.validate(); return true }
        guard AXIsProcessTrusted() else { throw AgentError.accessibility }
        var candidates = native.availableWindows(app: id)
        if candidates.isEmpty, launch {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { throw AgentError.invalidAction }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            for _ in 0..<12 {
                try Task.checkCancellation()
                candidates = native.availableWindows(app: id)
                if !candidates.isEmpty { break }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        if candidates.isEmpty, !launch { return false }
        let choices = candidates.map { candidate -> AutomaticTargeting.Window in
            let root = AXUIElementCreateApplication(candidate.pid)
            let focused = SelectedWindow.attribute(root, kAXFocusedWindowAttribute)
            let main = SelectedWindow.attribute(root, kAXMainWindowAttribute)
            return .init(id: candidate.id.uuidString,
                focused: focused.map { CFEqual($0, candidate.window) } ?? false,
                main: main.map { CFEqual($0, candidate.window) } ?? false)
        }
        guard let chosen = AutomaticTargeting.chooseWindow(choices),
              let selected = candidates.first(where: { $0.id.uuidString == chosen }) else {
            let name = applications.first(where: { $0.id == id })?.name ?? id
            throw AgentError.runtime(candidates.isEmpty
                ? "I opened \(name), but it has no accessible document window yet. Finish its welcome screen, then ask me to continue."
                : "There are several \(name) windows and none is active. Bring the intended document forward, then ask me to continue.")
        }
        external?.finish(); external = nil
        native.finish(); native.bind(selected)
        window = selected; lastObservation = nil
        let cli = Bundle.main.resourceURL?.appendingPathComponent("agent-desktop/agent-desktop")
        if let cli, FileManager.default.isExecutableFile(atPath: cli.path) {
            external = try AgentDesktopController(native: native, window: selected)
        }
        onApp(selected.name)
        return true
    }
    func observe(app: String?) async throws -> DesktopObservation {
        guard AXIsProcessTrusted() else { throw AgentError.accessibility }
        if let app, applications.contains(where: { $0.id == app }), window?.app != app {
            if try await !chooseApp(app, launch: false) {
                external?.finish(); external = nil
                native.finish(); native.bind(nil); window = nil
                onApp("")
            }
        }
        guard let window else {
            // No stale/foreign UI IDs. The planner can choose any installed app.
            let empty = DesktopObservation(app: "", name: "No app chosen yet", window: "",
                accessibility: true, truncated: false, elements: [])
            lastObservation = empty
            return empty
        }
        try window.validate()
        let result = try await (external as (any DesktopTools)? ?? native).observe(app: window.app)
        lastObservation = result
        return result
    }
    func confirmation(for action: PlannerAction, observation: DesktopObservation) -> String? {
        foregroundRequest = nil
        let existing = (external as (any DesktopTools)? ?? native).confirmation(for: action, observation: observation)
        if AutomaticTargeting.needsForeground(action), let window {
            foregroundRequest = action
            return "Brian needs to bring \(window.name) forward for this step. Continue?" + (existing.map { "\n\n" + $0 } ?? "")
        }
        return existing
    }
    func execute(_ action: PlannerAction, observation: DesktopObservation) async throws -> DesktopToolResult {
        try Task.checkCancellation()
        guard lastObservation == observation else { throw AgentError.invalidAction }
        try action.validate(observation: observation, apps: applications)
        if ["open_app", "search_mail"].contains(action.kind) {
            guard let id = AutomaticTargeting.destination(for: action, currentApp: window?.app) else { throw AgentError.invalidAction }
            _ = try await chooseApp(id, launch: true)
            if action.kind == "open_app" {
                return .init(app: id, message: "Brian chose the app and pinned its active document window. Observe it next; keep working until the full request is verified.")
            }
            let fresh = try await observe(app: id)
            return try await (external as (any DesktopTools)? ?? native).execute(action, observation: fresh)
        }
        if ["open_url", "search_web"].contains(action.kind) {
            // These explicit planner actions use the user's default browser.
            external?.finish(); external = nil; window = nil
            native.finish(); native.bind(nil)
            let result = try await native.execute(action, observation: observation)
            lastObservation = nil
            return result
        }
        guard let window else {
            if ["observe", "wait"].contains(action.kind) { return .init(app: nil, message: "Choose the app needed for the request using open_app.") }
            throw AgentError.runtime("I haven’t identified the app for this request yet. Please name what you want to work on.")
        }
        try window.validate()
        if AutomaticTargeting.needsForeground(action) {
            guard foregroundRequest == action else { throw AgentError.invalidAction }
            foregroundRequest = nil
            guard let app = NSRunningApplication(processIdentifier: window.pid),
                  AXUIElementPerformAction(window.window, kAXRaiseAction as CFString) == .success else { throw AgentError.invalidAction }
            app.activate(options: [])
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            let root = AXUIElementCreateApplication(window.pid)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid,
                  let focused = SelectedWindow.attribute(root, kAXFocusedWindowAttribute), CFEqual(focused, window.window) else {
                throw AgentError.runtime("The intended document could not be brought forward. No input was sent.")
            }
            native.bind(nil)
            defer { native.bind(self.window) }
            let fresh = action.kind == "vision_scroll" ? observation : try await native.observe(app: window.app)
            let result = try await native.execute(action, observation: fresh)
            if action.kind == "key", action.value == "cmd+n" {
                external?.finish(); external = nil; self.window = nil; lastObservation = nil
            }
            return result
        }
        return try await (external as (any DesktopTools)? ?? native).execute(action, observation: observation)
    }
}
