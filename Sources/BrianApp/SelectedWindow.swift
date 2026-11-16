import AppKit
import ApplicationServices
import BrianCore

@MainActor struct SelectedWindow: Identifiable {
    let id = UUID()
    let app: String
    let name: String
    let pid: pid_t
    let window: AXUIElement
    let title: String
    var scope: WindowScope { .init(app: app, title: title) }

    func validate() throws {
        guard let running = NSRunningApplication(processIdentifier: pid), running.bundleIdentifier == app,
              (Self.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []).contains(where: { CFEqual($0, window) }),
              Self.attribute(window, kAXMinimizedAttribute) as? Bool != true else {
            throw AgentError.runtime("The selected window closed or was minimized. Select a window again; Brian won’t switch to another one.")
        }
    }
    func contains(_ node: AXUIElement) -> Bool {
        var current: AXUIElement? = node
        for _ in 0..<40 {
            guard let item = current else { break }
            if CFEqual(item, window) { return true }
            guard let parent = Self.attribute(item, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        return false
    }
    func validateKeyboard() throws {
        try validate()
        let root = AXUIElementCreateApplication(pid)
        guard let focus = Self.attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focus) == AXUIElementGetTypeID(), contains(focus as! AXUIElement),
              let keyWindow = Self.attribute(root, kAXFocusedWindowAttribute) ?? Self.attribute(root, kAXMainWindowAttribute), CFEqual(keyWindow, window) else {
            throw AgentError.runtime("The selected window no longer owns its app’s keyboard focus. Brian stopped without changing your current app.")
        }
    }
    static func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
    }
}
