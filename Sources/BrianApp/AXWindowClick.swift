import AppKit
import ApplicationServices
import BrianCore

/// Uses semantic AX identity plus a current hit test; never model-generated coordinates.
enum AXWindowClick {
    static func click(_ node: AXUIElement, root: AXUIElement, window: AXUIElement, pid: pid_t,
                      background: Bool = false, matches: (AXUIElement) -> Bool) -> Bool {
        guard background || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, matches(node),
              let windowFrame = frame(window), let targetFrame = frame(node), windowFrame.contains(targetFrame),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let candidates = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(pid), (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(rect.minX - windowFrame.minX) < 2 && abs(rect.minY - windowFrame.minY) < 2 && abs(rect.width - windowFrame.width) < 2 && abs(rect.height - windowFrame.height) < 2
        }
        guard candidates.count == 1, let number = candidates[0][kCGWindowNumber as String] as? Int else { return false }
        let point = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) == .success else { return false }
        var verified = false
        for _ in 0..<7 {
            guard let current = hit else { break }
            if matches(current) { verified = true; break }
            guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            hit = (parent as! AXUIElement)
        }
        guard verified, matches(node), frame(node) == targetFrame,
              background || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let down = WindowPointerEvent.click(point: point, windowFrame: windowFrame, windowNumber: number, down: true),
              let up = WindowPointerEvent.click(point: point, windowFrame: windowFrame, windowNumber: number, down: false) else { return false }
        down.postToPid(pid); up.postToPid(pid)
        return true
    }
    private static func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
    }
    private static func frame(_ node: AXUIElement) -> CGRect? {
        guard let position = attribute(node, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(node, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
