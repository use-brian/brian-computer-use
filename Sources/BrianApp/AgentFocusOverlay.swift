import AppKit
import BrianCore

/// A separate, click-through surface: never steals focus or warps the real cursor.
@MainActor final class AgentFocusOverlay {
    var onTarget: ((CGRect?) -> Void)?
    var onAction: (() -> Void)?
    private var hasCursorTarget = false
    func pulse() { if hasCursorTarget { onAction?() } }
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
        let destination = cursor ? CompanionPlacement.cursorTarget(appKitRect, screen: screen.visibleFrame) : nil
        hasCursorTarget = destination != nil
        onTarget?(destination)
        panel.setFrame(frame, display: false)
        drawing.target = appKitRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        drawing.cursor = cursor; drawing.vision = vision
        drawing.needsDisplay = true
        panel.orderFrontRegardless()
    }
    func hide() { hasCursorTarget = false; panel.orderOut(nil); onTarget?(nil) }
}
private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
@MainActor private final class FocusDrawing: NSView {
    var target = CGRect.zero
    var cursor = false
    var vision = false
    override func draw(_ dirtyRect: NSRect) {
        guard !cursor else { return } // The small pointer is the action indicator.
        let color: NSColor = vision ? .systemOrange : .systemTeal
        // The pet and command bar carry status. Keep the target itself unobscured.
        let outline = NSBezierPath(roundedRect: target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
        color.withAlphaComponent(0.12).setStroke()
        outline.lineWidth = 1
        outline.stroke()

    }
}
