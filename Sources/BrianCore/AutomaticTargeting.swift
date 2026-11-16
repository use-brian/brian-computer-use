import Foundation

public enum AutomaticTargeting {
    public struct Window: Sendable {
        public let id: String
        public let focused: Bool
        public let main: Bool
        public init(id: String, focused: Bool = false, main: Bool = false) {
            self.id = id; self.focused = focused; self.main = main
        }
    }
    public static func chooseWindow(_ windows: [Window]) -> String? {
        if windows.count == 1 { return windows[0].id }
        let focused = windows.filter(\.focused)
        if focused.count == 1 { return focused[0].id }
        let main = windows.filter(\.main)
        return main.count == 1 ? main[0].id : nil
    }
    public static func destination(for action: PlannerAction, currentApp: String?) -> String? {
        switch action.kind {
        case "open_app": return action.app
        case "search_mail": return "com.apple.mail"
        default: return currentApp
        }
    }
    public static func needsForeground(_ action: PlannerAction) -> Bool {
        action.kind == "vision_scroll" || (action.kind == "key" &&
            !["return", "tab", "escape", "cmd+f", "cmd+a", "left", "right", "up", "down"].contains(action.value ?? ""))
    }
    public static let planningInstructions = """
    Brian chooses apps and windows automatically. Use open_app with an installed bundle ID when a different app is needed; search_mail automatically chooses Apple Mail. Do not ask the user to select an app, window mode, backend, or Mac mode. Use the current window for contextual requests; explicit requests override previous app choices. Each action is pinned to its current app window and normally runs in the background. If an action requires foreground input, Brian will request permission to bring that window forward. Choose another app when the task requires it; keep verifying the original request across app changes. Ask a concise question only for genuine ambiguity about the user's intent or document.
    """
}
