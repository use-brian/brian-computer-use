import AppKit
import BrianCore

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
        guard let rect, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }), rect.width > 0, rect.height > 0, let primary = NSScreen.screens.first else { hide(); return }
        // AX and ScreenCaptureKit use global Quartz points (top-left of primary display).
        let appKitRect = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let screen = NSScreen.screens.max { a, b in
            a.frame.intersection(appKitRect).area < b.frame.intersection(appKitRect).area
        } ?? primary
        let frame = appKitRect.insetBy(dx: -5, dy: -5).intersection(screen.frame)
        guard !frame.isNull, !frame.isEmpty else { hide(); return }
        // Window inspection is a highlight, not a destination for the pet.
        onTarget?(cursor ? CompanionPlacement.visibleTarget(appKitRect, screen: screen.visibleFrame) : nil)
        panel.setFrame(frame, display: false)
        drawing.target = appKitRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        drawing.cursor = cursor; drawing.vision = vision
        drawing.needsDisplay = true
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil); onTarget?(nil) }
}
private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
@MainActor private final class FocusDrawing: NSView {
    var target = CGRect.zero
    var cursor = false
    var vision = false
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = vision ? .systemOrange : .systemTeal
        // The pet and command bar carry status. Keep the target itself unobscured.
        let outline = NSBezierPath(roundedRect: target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
        color.withAlphaComponent(cursor ? 0.45 : 0.22).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        if cursor {
            let ring = NSBezierPath(ovalIn: CGRect(x: target.midX - 5, y: target.midY - 5, width: 10, height: 10))
            color.withAlphaComponent(0.55).setStroke()
            ring.lineWidth = 1
            ring.stroke()
        }
    }
}
