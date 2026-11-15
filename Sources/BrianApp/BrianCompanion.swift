import AppKit
import SwiftUI

enum BrianMood { case idle, working, happy, attention }

/// The existing Use Brian pixel silhouette, drawn as native shapes so the eyes,
/// feet and body can animate independently without altering the brand artwork.
struct BrianAvatar: View {
    var mood: BrianMood = .idle
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated || reduceMotion)) { timeline in
            let time = animated && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                let cell = min(size.width / 9, size.height / 8)
                let bounce = time == 0 ? 0 : sin(time * (mood == .working ? 7 : 2.4)) * (mood == .working ? 3.2 : 1.8)
                let origin = CGPoint(x: (size.width - cell * 7) / 2, y: cell * 0.7 + bounce)
                let cyan = Color(red: 0, green: 0.83, blue: 0.92)
                let ink = Color(red: 0.025, green: 0.14, blue: 0.20)
                let rows = [2...4, 1...5, 0...6, 0...6, 1...5]

                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.24, y: cell * 7.25,
                                                     width: size.width * 0.52, height: cell * 0.36)),
                             with: .color(.black.opacity(0.12)))
                for (row, columns) in rows.enumerated() {
                    for column in columns {
                        let rect = CGRect(x: origin.x + Double(column) * cell, y: origin.y + Double(row) * cell,
                                          width: cell - 0.5, height: cell - 0.5)
                        context.fill(Path(rect), with: .color(cyan))
                    }
                }
                for column in [2, 4] {
                    let kick = mood == .working && time != 0 ? sin(time * 7 + Double(column)) * 2.5 : 0
                    context.fill(Path(CGRect(x: origin.x + Double(column) * cell,
                                             y: origin.y + 5 * cell + kick, width: cell - 0.5, height: cell - 0.5)),
                                 with: .color(cyan))
                }
                let blink = time != 0 && time.truncatingRemainder(dividingBy: 4.5) < 0.16
                for column in [2, 4] {
                    let eyeHeight = blink || mood == .happy ? cell * 0.12 : cell * 0.46
                    let eye = CGRect(x: origin.x + Double(column) * cell + cell * 0.27,
                                     y: origin.y + cell * 2.28, width: cell * 0.46, height: eyeHeight)
                    context.fill(Path(eye), with: .color(ink))
                }
                if mood == .happy {
                    var smile = Path()
                    smile.move(to: CGPoint(x: origin.x + cell * 3, y: origin.y + cell * 3.25))
                    smile.addQuadCurve(to: CGPoint(x: origin.x + cell * 4, y: origin.y + cell * 3.25),
                                       control: CGPoint(x: origin.x + cell * 3.5, y: origin.y + cell * 3.8))
                    context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: cell * 0.14, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CompanionView: View {
    @ObservedObject var model: CommandModel
    let open: () -> Void
    let didMove: () -> Void
    let hide: () -> Void
    @State private var hovering = false

    private var mood: BrianMood {
        model.isRunning ? .working : model.hasError ? .attention : model.isVerified ? .happy : .idle
    }
    private var label: String {
        model.isRunning ? "Working…" : model.hasError ? "Needs you" : model.isVerified ? "Done!" : "Hey, I’m Brian"
    }
    private var interaction: CompanionInteraction {
        let stopAction: (() -> Void)? = model.isRunning ? { model.stop() } : nil
        return CompanionInteraction(label: label, open: open, stop: stopAction,
            hide: hide, didMove: didMove, hover: { hovering = $0 })
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .opacity(hovering || model.isRunning || model.hasError || model.isVerified ? 1 : 0)
            BrianAvatar(mood: mood).frame(width: 122, height: 110)
        }
        .frame(width: 146, height: 138)
        .overlay { interaction }
    }
}

/// Handle input in AppKit so window motion cannot feed back into gesture
/// translation. Pointer and window origins are captured once in screen space.
private struct CompanionInteraction: NSViewRepresentable {
    let label: String
    let open: () -> Void
    let stop: (() -> Void)?
    let hide: () -> Void
    let didMove: () -> Void
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> CompanionInputView { CompanionInputView() }

    func updateNSView(_ view: CompanionInputView, context: Context) {
        view.open = open
        view.stop = stop
        view.hide = hide
        view.didMove = didMove
        view.hover = hover
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Brian companion")
        view.setAccessibilityValue(label)
        view.setAccessibilityHelp("Click to give Brian a task. Drag to move. Right-click for options.")
    }
}

private final class CompanionInputView: NSView {
    var open: () -> Void = {}
    var stop: (() -> Void)?
    var hide: () -> Void = {}
    var didMove: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    private var pointerOrigin: CGPoint?
    private var windowOrigin = CGPoint.zero
    private var dragging = false
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        pointerOrigin = NSEvent.mouseLocation
        windowOrigin = window.frame.origin
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pointerOrigin, let window else { return }
        let pointer = NSEvent.mouseLocation
        let dx = pointer.x - pointerOrigin.x
        let dy = pointer.y - pointerOrigin.y
        guard dragging || dx * dx + dy * dy >= 25 else { return }
        dragging = true
        NSCursor.closedHand.set()
        // Clamp only on release: edges and monitor boundaries must not make
        // the pet stick or change the offset under the pointer during a drag.
        window.setFrameOrigin(CGPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard pointerOrigin != nil else { return }
        let wasDragging = dragging
        pointerOrigin = nil
        dragging = false
        NSCursor.openHand.set()
        if wasDragging { didMove() }
        else { open() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = menu.addItem(withTitle: "Open Brian", action: #selector(openBrian), keyEquivalent: "")
        openItem.target = self
        if stop != nil {
            let stopItem = menu.addItem(withTitle: "Stop task", action: #selector(stopTask), keyEquivalent: "")
            stopItem.target = self
        }
        let hideItem = menu.addItem(withTitle: "Hide companion", action: #selector(hideCompanion), keyEquivalent: "")
        hideItem.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool { open(); return true }
    @objc private func openBrian() { open() }
    @objc private func stopTask() { stop?() }
    @objc private func hideCompanion() { hide() }
}

@MainActor
final class CompanionController {
    private let panel: NSPanel

    init(model: CommandModel, open: @escaping () -> Void) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 146, height: 138),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Brian companion"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: CompanionView(model: model, open: open,
            didMove: { [weak self] in self?.finishMove() },
            hide: { [weak self] in self?.panel.orderOut(nil) }))
    }

    func show() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let saved = UserDefaults.standard.array(forKey: "companionPosition") as? [Double]
        let position = saved?.count == 2 ? CGPoint(x: saved![0], y: saved![1])
            : CGPoint(x: screen.maxX - 166, y: screen.minY + 50)
        let targetScreen = NSScreen.screens.first { $0.visibleFrame.contains(position) }?.visibleFrame ?? screen
        panel.setFrameOrigin(clamp(position, to: targetScreen))
        panel.orderFrontRegardless()
    }

    private func finishMove() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        if let screen { panel.setFrameOrigin(clamp(panel.frame.origin, to: screen)) }
        UserDefaults.standard.set([panel.frame.minX, panel.frame.minY], forKey: "companionPosition")
    }

    private func clamp(_ point: CGPoint, to screen: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, screen.minX), max(screen.minX, screen.maxX - panel.frame.width)),
                y: min(max(point.y, screen.minY), max(screen.minY, screen.maxY - panel.frame.height)))
    }
}
