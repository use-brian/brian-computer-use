import Foundation

/// A selected window is a hard execution boundary, not just planner context.
public struct WindowScope: Codable, Sendable, Equatable {
    public let app: String
    public let title: String
    public init(app: String, title: String) { self.app = app; self.title = title }
    public func validate(_ action: PlannerAction) throws {
        switch action.kind {
        case "open_url", "search_web", "vision_scroll":
            throw AgentError.runtime("This action needs foreground control. Choose Mac in Brian’s target menu to run it there.")
        case "open_app":
            guard action.app == app else { throw AgentError.runtime("This task is restricted to the selected window. Select another window or choose Mac to work across apps.") }
        case "search_mail":
            guard app == "com.apple.mail" else { throw AgentError.runtime("Select a Mail window to search email in window mode.") }
        case "key":
            guard ["return", "tab", "escape", "cmd+f", "cmd+a", "left", "right", "up", "down"].contains(action.value ?? "") else {
                throw AgentError.runtime("That shortcut can affect other windows or the shared clipboard. Use Mac mode for this action.")
            }
        default: break
        }
    }
}
