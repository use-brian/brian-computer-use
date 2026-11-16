import Foundation

/// A selected window is a hard execution boundary, not just planner context.
public struct WindowScope: Codable, Sendable, Equatable {
    public let app: String
    public let title: String
    public init(app: String, title: String) { self.app = app; self.title = title }
    public func validate(_ action: PlannerAction) throws {
        switch action.kind {
        case "open_url", "search_web", "vision_scroll":
            throw AgentError.runtime("This action requires foreground control of the current window.")
        case "open_app":
            guard action.app == app else { throw AgentError.runtime("This action is pinned to a different window. Brian must switch apps before dispatch.") }
        case "search_mail":
            guard app == "com.apple.mail" else { throw AgentError.runtime("Brian must choose a Mail window before searching email.") }
        case "key":
            guard ["return", "tab", "escape", "cmd+f", "cmd+a", "left", "right", "up", "down"].contains(action.value ?? "") else {
                throw AgentError.runtime("That shortcut requires foreground control because it can affect other windows or the shared clipboard.")
            }
        default: break
        }
    }
}
