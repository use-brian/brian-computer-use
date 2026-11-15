import AppKit
import ApplicationServices
import BrianCore

/// A narrow, read-only Mail workflow. It changes search controls, never
/// composes, sends, deletes, or interprets email contents as instructions.
@MainActor
struct MailSearchExecutor {
    var onTarget: ((AXUIElement, String) -> Void)?
    func execute(_ request: MailSearchRequest) async throws {
        guard AXIsProcessTrusted() else { throw AgentError.accessibility }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else {
            throw failure("Apple Mail isn’t installed.")
        }
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        let window = try await waitFor {
            let viewers = (attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                string($0, kAXIdentifierAttribute).hasPrefix("Mail.messageViewer.window.")
            }
            if let focused = attribute(root, kAXFocusedWindowAttribute),
               let viewer = viewers.first(where: { CFEqual($0, focused) }) { return viewer }
            if let main = attribute(root, kAXMainWindowAttribute),
               let viewer = viewers.first(where: { CFEqual($0, main) }) { return viewer }
            return viewers.first { attribute($0, kAXMainAttribute) as? Bool == true }
                ?? viewers.first { attribute($0, kAXFocusedAttribute) as? Bool == true }
                ?? (viewers.count == 1 ? viewers[0] : nil)
        }
        try Task.checkCancellation()
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            throw failure("Could not bring the intended Mail window forward.")
        }
        app.activate(options: [])
        try await Task.sleep(for: .milliseconds(200))
        guard let toolbar = find(window, matching: { string($0, kAXRoleAttribute) == kAXToolbarRole }),
              let field = find(toolbar, matching: {
                  string($0, kAXSubroleAttribute) == "AXSearchField" || string($0, kAXRoleAttribute) == "AXSearchField"
              }) else { throw failure("Open Mail’s main window with its search field visible, then retry.") }
        onTarget?(field, "Searching Mail")
        try await Task.sleep(for: .milliseconds(300))
        try set(field, kAXFocusedAttribute, kCFBooleanTrue)
        guard let focused = attribute(root, kAXFocusedUIElementAttribute), CFEqual(focused, field) else {
            throw failure("Mail’s search field did not receive focus. No search was submitted.")
        }
        // AXValue alone can change the displayed text without notifying Mail's
        // search controller. Enter real text into the verified focused field.
        try key(0, app: app, flags: .maskCommand)
        try await Task.sleep(for: .milliseconds(60))
        try key(51, app: app)
        try await Task.sleep(for: .milliseconds(100))
        // Submit short Unicode runs so Mail's live suggestions cannot interrupt
        // between every letter. Keep complete characters (including surrogate pairs).
        var chunks: [String] = []
        var chunk = ""
        for character in request.query {
            if !chunk.isEmpty, chunk.utf16.count + String(character).utf16.count > 16 { chunks.append(chunk); chunk = "" }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        for chunk in chunks {
            try Task.checkCancellation()
            guard let focus = attribute(root, kAXFocusedUIElementAttribute), CFEqual(focus, field),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                throw failure("Mail’s search focus changed. Stopped before continuing.")
            }
            let units = Array(chunk.utf16)
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { throw failure("Search text input is unavailable.") }
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            down.flags = []; up.flags = []
            down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(200))
        guard string(field, kAXValueAttribute) == request.query else {
            throw failure("Mail didn’t accept the search text. Nothing else was changed.")
        }
        try key(36, app: app) // Return commits the search; targeted to Mail only.
        try await Task.sleep(for: .milliseconds(600))
        let allMailboxes = try await waitFor {
            guard let outline = find(window, matching: { string($0, kAXIdentifierAttribute) == "MailboxesOutlineView" }) else { return nil }
            return find(outline, matching: { node in
                string(node, kAXRoleAttribute) == kAXRowRole && named(node, "All Mailboxes")
            })
        }
        onTarget?(allMailboxes, "All Mailboxes")
        guard let outline = find(window, matching: { string($0, kAXIdentifierAttribute) == "MailboxesOutlineView" }),
              let freshScope = find(outline, matching: { string($0, kAXRoleAttribute) == kAXRowRole && named($0, "All Mailboxes") }),
              AXWindowClick.click(freshScope, root: root, window: window, pid: app.processIdentifier,
                  matches: { string($0, kAXRoleAttribute) == kAXRowRole && named($0, "All Mailboxes") }) else {
            throw failure("Mail’s All Mailboxes control moved or is not visible. Please leave the search window in front.")
        }
        _ = try await waitFor {
            guard let outline = find(window, matching: { string($0, kAXIdentifierAttribute) == "MailboxesOutlineView" }),
                  let current = find(outline, matching: { string($0, kAXRoleAttribute) == kAXRowRole && named($0, "All Mailboxes") }) else { return nil }
            let selected = (attribute(outline, kAXSelectedRowsAttribute) as? [AXUIElement] ?? []) + (attribute(outline, kAXSelectedChildrenAttribute) as? [AXUIElement] ?? [])
            let scope = string(window, kAXTitleAttribute) + " " + string(window, kAXDescriptionAttribute)
            return attribute(current, kAXSelectedAttribute) as? Bool == true || selected.contains(where: { named($0, "All Mailboxes") }) || scope.contains("All Mailboxes") ? current : nil
        }
        // Searching must not open menu tracking or alter the user's sort order.
        // The previous automatic sort verification stranded View > Sort By.
        let currentWindows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let main = attribute(root, kAXFocusedWindowAttribute).flatMap { focused in currentWindows.first { CFEqual($0, focused) } }
            ?? currentWindows.first { attribute($0, kAXMainAttribute) as? Bool == true }
        guard main.map({ CFEqual($0, window) }) == true,
              string(field, kAXValueAttribute) == request.query else {
            throw failure("Mail opened the search, but its window or query changed before verification. Review its results.")
        }
    }

    private func named(_ node: AXUIElement, _ name: String) -> Bool {
        let nodes = [node] + (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        return nodes.contains { item in
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains { string(item, $0) == name }
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
    private func key(_ code: CGKeyCode, app: NSRunningApplication, flags: CGEventFlags = []) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            throw failure("Mail lost focus. Retry when its main window is in front.")
        }
        down.flags = flags; up.flags = flags
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
    }
    private func failure(_ message: String) -> AgentError { .runtime(message) }
}
