import AppKit

/// A separate, click-through surface: never steals focus or warps the real cursor.
@MainActor final class AgentFocusOverlay {
    var onTarget: ((CGRect?) -> Void)?
    private let panel: NSPanel
    private let drawing = FocusDrawing()
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false; panel.contentView = drawing
        drawing.setAccessibilityHidden(true)
    }
    func show(rect: CGRect?, label: String, cursor: Bool = false, vision: Bool = false) {
        guard let rect, rect.width > 0, rect.height > 0, let primary = NSScreen.screens.first else { hide(); return }
        // AX and ScreenCaptureKit use global Quartz points (top-left of primary display).
        let appKitRect = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        onTarget?(appKitRect)
        let screen = NSScreen.screens.max { a, b in
            a.frame.intersection(appKitRect).area < b.frame.intersection(appKitRect).area
        } ?? primary
        let union = appKitRect.insetBy(dx: -8, dy: -8)
            .union(NSRect(x: appKitRect.minX - 8, y: appKitRect.maxY + 4, width: 290, height: 30))
        let frame = union.intersection(screen.frame)
        guard !frame.isEmpty else { hide(); return }
        panel.setFrame(frame, display: false)
        drawing.target = appKitRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        drawing.label = String(label.prefix(52)); drawing.cursor = cursor; drawing.vision = vision
        drawing.needsDisplay = true
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil); onTarget?(nil) }
}
private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
@MainActor private final class FocusDrawing: NSView {
    var target = CGRect.zero
    var label = ""
    var cursor = false
    var vision = false
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = vision ? .systemOrange : .systemTeal
        color.withAlphaComponent(0.07).setFill()
        let outline = NSBezierPath(roundedRect: target.insetBy(dx: -3, dy: -3), xRadius: 7, yRadius: 7)
        outline.fill(); color.withAlphaComponent(0.9).setStroke(); outline.lineWidth = 2; outline.stroke()
        if cursor {
            let point = CGPoint(x: target.midX, y: target.midY)
            let ring = NSBezierPath(ovalIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
            NSColor.white.withAlphaComponent(0.95).setFill(); ring.fill(); color.setStroke(); ring.lineWidth = 3; ring.stroke()
            color.setFill(); NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
        }
        let text = (vision ? "Vision · " : "Accessibility · ") + label
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let width = min(bounds.width, size.width + 20)
        let bubble = CGRect(x: max(0, min(target.minX - 3, bounds.width - width)),
                            y: max(0, min(target.maxY + 7, bounds.height - 26)), width: width, height: 26)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(in: bubble.insetBy(dx: 10, dy: 5), withAttributes: attrs)
    }
}
