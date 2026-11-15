import AppKit
import ApplicationServices
import BrianCore

/// A narrow, read-only Mail workflow. It changes search/sort controls, never
/// composes, sends, deletes, or interprets email contents as instructions.
@MainActor
struct MailSearchExecutor {
    func execute(_ request: MailSearchRequest) async throws {
        guard AXIsProcessTrusted() else { throw AgentError.accessibility }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else {
            throw failure("Apple Mail isn’t installed.")
        }
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        let window = try await waitFor {
            (attribute(root, kAXWindowsAttribute) as? [AXUIElement])?.first {
                string($0, kAXIdentifierAttribute).hasPrefix("Mail.messageViewer.window.")
            }
        }
        try Task.checkCancellation()
        guard let toolbar = find(window, matching: { string($0, kAXRoleAttribute) == kAXToolbarRole }),
              let field = find(toolbar, matching: {
                  string($0, kAXSubroleAttribute) == "AXSearchField" || string($0, kAXRoleAttribute) == "AXSearchField"
              }) else { throw failure("Open Mail’s main window with its search field visible, then retry.") }
        try set(field, kAXFocusedAttribute, kCFBooleanTrue)
        try set(field, kAXValueAttribute, request.query as CFString)
        guard string(field, kAXValueAttribute) == request.query else {
            throw failure("Mail didn’t accept the search text. Nothing else was changed.")
        }
        try key(36, app: app) // Return commits the search; targeted to Mail only.
        let allMailboxes = try await waitFor {
            guard let outline = find(window, matching: { string($0, kAXIdentifierAttribute) == "MailboxesOutlineView" }) else { return nil }
            return find(outline, matching: { node in
                string(node, kAXRoleAttribute) == kAXRowRole && named(node, "All Mailboxes")
            })
        }
        try set(allMailboxes, kAXSelectedAttribute, kCFBooleanTrue)
        try await Task.sleep(for: .milliseconds(300))
        guard attribute(allMailboxes, kAXSelectedAttribute) as? Bool == true else {
            throw failure("Select All Mailboxes in Mail, then retry the search.")
        }
        try await selectSort("Mail.menuBar.viewMenu.sortBy.date", root: root, app: app)
        try await selectSort("Mail.menuBar.viewMenu.sortBy.descending", root: root, app: app)
        let menu = try await sortMenu(root: root)
        let date = find(menu, matching: { string($0, kAXIdentifierAttribute) == "Mail.menuBar.viewMenu.sortBy.date" })
        let descending = find(menu, matching: { string($0, kAXIdentifierAttribute) == "Mail.menuBar.viewMenu.sortBy.descending" })
        let sorted = date.map { !string($0, kAXMenuItemMarkCharAttribute).isEmpty } == true &&
            descending.map { !string($0, kAXMenuItemMarkCharAttribute).isEmpty } == true
        try key(53, app: app)
        try key(53, app: app)
        guard sorted, string(field, kAXValueAttribute) == request.query else {
            throw failure("Mail opened the search, but I couldn’t verify newest-first ordering. Review its results.")
        }
    }

    private func named(_ node: AXUIElement, _ name: String) -> Bool {
        let nodes = [node] + (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        return nodes.contains { item in
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains { string(item, $0) == name }
        }
    }
    private func sortMenu(root: AXUIElement) async throws -> AXUIElement {
        guard let value = attribute(root, kAXMenuBarAttribute) else { throw failure("Mail’s menu bar is unavailable.") }
        let menuBar = value as! AXUIElement
        guard let view = find(menuBar, matching: { string($0, kAXIdentifierAttribute) == "Mail.menuBar.viewMenu" }) else {
            throw failure("Mail’s View menu is unavailable.")
        }
        try press(view)
        let sort = try await waitFor { find(view, matching: { string($0, kAXIdentifierAttribute) == "Mail.menuBar.viewMenu.sortBy" }) }
        try press(sort)
        return sort
    }
    private func selectSort(_ identifier: String, root: AXUIElement, app: NSRunningApplication) async throws {
        let menu = try await sortMenu(root: root)
        let item = try await waitFor { find(menu, matching: { string($0, kAXIdentifierAttribute) == identifier }) }
        if string(item, kAXMenuItemMarkCharAttribute).isEmpty { try press(item) }
        else { try key(53, app: app); try key(53, app: app) }
        try await Task.sleep(for: .milliseconds(200))
    }
    private func press(_ node: AXUIElement) throws {
        try Task.checkCancellation()
        guard AXUIElementPerformAction(node, kAXPressAction as CFString) == .success else {
            throw failure("Mail’s search controls changed. Please retry from its main window.")
        }
    }

    private func set(_ node: AXUIElement, _ name: String, _ value: CFTypeRef) throws {
        try Task.checkCancellation()
        guard AXUIElementSetAttributeValue(node, name as CFString, value) == .success else {
            throw failure("Mail’s search controls changed. Please retry from its main window.")
        }
    }
    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ node: AXUIElement, _ name: String) -> String { attribute(node, name) as? String ?? "" }
    private func find(_ root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [root]
        var index = 0
        while index < queue.count && index < 350 {
            let node = queue[index]
            index += 1
            if predicate(node) { return node }
            // Never walk message bodies or message rows; only app chrome.
            if ["AXWebArea", kAXTableRole].contains(string(node, kAXRoleAttribute)) { continue }
            queue += (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(150)
        }
        return nil
    }
    private func waitFor(_ lookup: () -> AXUIElement?) async throws -> AXUIElement {
        for _ in 0..<30 {
            try Task.checkCancellation()
            if let result = lookup() { return result }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw failure("Mail’s search controls aren’t ready. Open Mail and retry.")
    }
    private func key(_ code: CGKeyCode, app: NSRunningApplication) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            throw failure("Mail lost focus. Retry when its main window is in front.")
        }
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
    }
    private func failure(_ message: String) -> AgentError { .runtime(message) }
}
