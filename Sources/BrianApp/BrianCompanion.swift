import AppKit
import SwiftUI
import Combine
import BrianCore

enum BrianMood { case idle, working, running, happy, attention }

/// The existing Use Brian pixel silhouette, drawn as native shapes so the eyes,
/// feet and body can animate independently without altering the brand artwork.
struct BrianAvatar: View {
    var mood: BrianMood = .idle
    var animated = true
    var direction: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated || reduceMotion)) { timeline in
            let time = animated && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                let cell = min(size.width / 9, size.height / 8)
                let moving = mood == .running
                let bounce = time == 0 ? 0 : sin(time * (moving ? 22 : mood == .working ? 7 : 2.4)) * (moving ? cell * 0.18 : mood == .working ? 3.2 : 1.8)
                if moving {
                    context.translateBy(x: size.width/2, y: size.height/2)
                    context.rotate(by: .degrees(Double(direction) * 8))
                    context.translateBy(x: -size.width/2, y: -size.height/2)
                }
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
                    let kick = time == 0 ? 0 : moving ? sin(time * 22 + (column == 2 ? 0 : .pi)) * cell * 0.38 : mood == .working ? sin(time * 7 + Double(column)) * 2.5 : 0
                    context.fill(Path(CGRect(x: origin.x + Double(column) * cell,
                                             y: origin.y + 5 * cell + kick, width: cell - 0.5, height: cell - 0.5)),
                                 with: .color(cyan))
                }
                let blink = time != 0 && time.truncatingRemainder(dividingBy: 4.5) < 0.16
                for column in [2, 4] {
                    let eyeHeight = blink || mood == .happy ? cell * 0.12 : cell * 0.46
                    let eye = CGRect(x: origin.x + Double(column) * cell + cell * (moving ? 0.27 + direction * 0.1 : 0.27),
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

@MainActor final class CompanionMotion: ObservableObject {
    @Published var compact = false
    @Published var moving = false
    @Published var direction: CGFloat = 1
}

struct CompanionView: View {
    @ObservedObject var model: CommandModel
    @ObservedObject var motion: CompanionMotion
    let willInteract: () -> Void
    let open: () -> Void
    let didMove: (Bool) -> Void
    let readReply: () -> Void
    let hide: () -> Void
    @State private var hovering = false

    private var mood: BrianMood {
        model.isRunning ? .working : model.hasError ? .attention : model.isFinished ? .happy : .idle
    }
    private var label: String {
        model.isRunning ? (model.status.hasPrefix("Looking") || model.status.hasPrefix("Using vision") ? "Looking…" : model.status.hasPrefix("Understanding") ? "Thinking…" : "Working…") : model.hasError ? "Needs you" : model.isFinished ? "Done!" : "Hey, I’m Brian"
    }
    private var interaction: CompanionInteraction {
        let stopAction: (() -> Void)? = model.isRunning ? { model.stop() } : nil
        return CompanionInteraction(label: label, willInteract: willInteract, open: open, stop: stopAction,
            hide: hide, didMove: didMove, readReply: model.hasResponse && !model.isRunning ? readReply : nil, hover: { hovering = $0 })
    }
    var body: some View {
        VStack(spacing: 0) {
            if !motion.compact { Text(motion.moving ? "On my way…" : label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .opacity(hovering || motion.moving || model.isRunning || (model.hasError && !model.hasResponse) ? 1 : 0)
            }
            BrianAvatar(mood: motion.moving ? .running : mood, direction: motion.direction)
                .frame(width: motion.compact ? 38 : 80, height: motion.compact ? 38 : 72)
        }
        .frame(width: motion.compact ? 44 : 96, height: motion.compact ? 44 : 100)
        .overlay { interaction }
    }
}

/// Handle input in AppKit so window motion cannot feed back into gesture
/// translation. Pointer and window origins are captured once in screen space.
private struct CompanionInteraction: NSViewRepresentable {
    let label: String
    let willInteract: () -> Void
    let open: () -> Void
    let stop: (() -> Void)?
    let hide: () -> Void
    let didMove: (Bool) -> Void
    let readReply: (() -> Void)?
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> CompanionInputView { CompanionInputView() }

    func updateNSView(_ view: CompanionInputView, context: Context) {
        view.willInteract = willInteract
        view.open = open
        view.stop = stop
        view.hide = hide
        view.didMove = didMove
        view.readReply = readReply
        view.hover = hover
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Brian companion")
        view.setAccessibilityValue(label)
        view.setAccessibilityHelp("Click to give Brian a task. Drag to move. Right-click for options.")
    }
}

private final class CompanionInputView: NSView {
    var willInteract: () -> Void = {}
    var open: () -> Void = {}
    var stop: (() -> Void)?
    var hide: () -> Void = {}
    var didMove: (Bool) -> Void = { _ in }
    var readReply: (() -> Void)?
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
        willInteract()
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
        didMove(wasDragging)
        if !wasDragging { open() }
    }

    override func rightMouseDown(with event: NSEvent) {
        willInteract()
        defer { didMove(false) }
        let menu = NSMenu()
        let openItem = menu.addItem(withTitle: "Open Brian", action: #selector(openBrian), keyEquivalent: "")
        openItem.target = self
        if readReply != nil {
            let replyItem = menu.addItem(withTitle: "Read last reply", action: #selector(showReply), keyEquivalent: "")
            replyItem.target = self
        }
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
    @objc private func showReply() { readReply?() }
    @objc private func stopTask() { stop?() }
    @objc private func hideCompanion() { hide() }
}

@MainActor
final class CompanionController {
    private let panel: NSPanel
    private let model: CommandModel
    private let motion = CompanionMotion()
    private let reply = CompanionReplyController()
    private var dismissedReplyVersion: Int?
    private var subscriptions = Set<AnyCancellable>()
    private var movement: Task<Void, Never>?
    private var movementID = UUID()
    private var bar: CGRect?
    private var restingFrame: CGRect?
    private var hiddenByUser = false
    private var manualUntil = Date.distantPast
    private var interacting = false
    private let normalSize = CGSize(width: 96, height: 100)
    private let cursorSize = CGSize(width: 44, height: 44)

    init(model: CommandModel, open: @escaping () -> Void) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 96, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Brian companion"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: CompanionView(model: model, motion: motion,
            willInteract: { [weak self] in self?.beginInteraction() }, open: open,
            didMove: { [weak self] dragged in self?.finishMove(dragged: dragged) },
            readReply: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissedReplyVersion = nil
                    self.updateReply()
                    self.reply.focus()
                }
            }, hide: { [weak self] in self?.hide() }))
        model.$responseVersion.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateReply() }
        }.store(in: &subscriptions)
        model.$hasResponse.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.updateReply() }
        }.store(in: &subscriptions)
        model.$activityTarget.compactMap { $0 }.sink { [weak self] rect in
            Task { @MainActor in self?.follow(rect) }
        }.store(in: &subscriptions)
        model.$isRunning.removeDuplicates().dropFirst().sink { [weak self] running in
            Task { @MainActor in self?.workChanged(running) }
        }.store(in: &subscriptions)
    }

    func show() {
        movement?.cancel(); movementID = UUID(); motion.moving = false
        hiddenByUser = false
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let saved = UserDefaults.standard.array(forKey: "companionPosition") as? [Double]
        let point = saved?.count == 2 ? CGPoint(x: saved![0], y: saved![1]) : CGPoint(x: screen.maxX-normalSize.width-20, y: screen.minY+50)
        let targetScreen = NSScreen.screens.first { $0.visibleFrame.contains(point) }?.visibleFrame ?? screen
        motion.compact = model.isRunning
        panel.setFrame(CompanionPlacement.clamp(CGRect(origin: point, size: model.isRunning ? cursorSize : normalSize), to: targetScreen), display: true)
        restingFrame = panel.frame
        panel.orderFrontRegardless()
        updateReply()
    }

    func runToBar(_ frame: CGRect) {
        bar = frame
        guard !hiddenByUser else { return }
        manualUntil = .distantPast
        let size = model.isRunning ? cursorSize : normalSize
        motion.compact = model.isRunning
        move(to: CompanionPlacement.byBar(frame, size: size, screen: screen(for: frame)))
    }

    func barClosed() {
        bar = nil
        guard !model.isRunning else { return }
        returnToSide()
    }

    private func returnToSide() {
        guard !hiddenByUser, !interacting else { return }
        motion.compact = false
        let home = restingFrame ?? panel.frame
        move(to: CompanionPlacement.atSide(home, size: normalSize, screen: screen(for: home)))
    }

    private func follow(_ target: CGRect) {
        guard model.isRunning, !hiddenByUser, !interacting, Date() >= manualUntil else { return }
        motion.compact = true
        move(to: CompanionPlacement.beside(target, size: cursorSize, screen: screen(for: target)))
    }

    private func workChanged(_ running: Bool) {
        if running { reply.hide() }
        guard !hiddenByUser, !interacting else { return }
        if running {
            motion.compact = true
            if let target = model.activityTarget { follow(target) }
            else { move(to: CGRect(x: panel.frame.midX-cursorSize.width/2, y: panel.frame.midY-cursorSize.height/2, width: cursorSize.width, height: cursorSize.height)) }
        } else {
            motion.compact = false
            if let bar { runToBar(bar) }
            else { returnToSide() }
        }
    }

    private func move(to destination: CGRect) {
        reply.hide()
        movement?.cancel()
        let id = UUID(); movementID = id
        let start = panel.frame
        let distance = hypot(destination.midX-start.midX, destination.midY-start.midY)
        motion.direction = destination.midX >= start.midX ? 1 : -1
        panel.orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, distance > 3 || start.size != destination.size else {
            panel.setFrame(destination, display: true); motion.moving = false; updateReply(); return
        }
        motion.moving = true
        let duration = motion.compact ? min(0.30, max(0.15, distance/2400)) : min(0.85, max(0.2, distance/950))
        movement = Task { [weak self] in
            let began = Date()
            while !Task.isCancelled {
                guard let self, movementID == id else { return }
                let t = min(1, Date().timeIntervalSince(began)/duration)
                let ease = t*t*(3-2*t)
                panel.setFrame(CGRect(x: start.minX+(destination.minX-start.minX)*ease,
                    y: start.minY+(destination.minY-start.minY)*ease,
                    width: start.width+(destination.width-start.width)*ease,
                    height: start.height+(destination.height-start.height)*ease), display: true)
                if t >= 1 { motion.moving = false; updateReply(); return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func updateReply() {
        guard !hiddenByUser, !interacting, !motion.moving, !model.isRunning,
              model.hasResponse, !model.status.isEmpty,
              dismissedReplyVersion != model.responseVersion else { reply.hide(); return }
        reply.show(text: model.status, beside: panel.frame, screen: screen(for: panel.frame)) { [weak self] in
            guard let self else { return }
            dismissedReplyVersion = model.responseVersion
            reply.hide()
        }
    }

    private func screen(for frame: CGRect) -> CGRect {
        NSScreen.screens.max { a, b in
            let x = a.visibleFrame.intersection(frame), y = b.visibleFrame.intersection(frame)
            return (x.isNull ? 0 : x.width*x.height) < (y.isNull ? 0 : y.width*y.height)
        }?.visibleFrame ?? frame
    }
    private func beginInteraction() {
        reply.hide()
        movement?.cancel(); movementID = UUID(); motion.moving = false
        interacting = true
        manualUntil = Date().addingTimeInterval(2)
    }
    private func finishMove(dragged: Bool) {
        defer { updateReply() }
        interacting = false
        manualUntil = Date().addingTimeInterval(2)
        if motion.compact && !model.isRunning {
            motion.compact = false
            panel.setFrame(CompanionPlacement.clamp(CGRect(origin: panel.frame.origin, size: normalSize), to: screen(for: panel.frame)), display: true)
        }
        guard dragged else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.visibleFrame ?? screen(for: panel.frame)
        panel.setFrame(CompanionPlacement.clamp(panel.frame, to: screen), display: true)
        restingFrame = panel.frame
        UserDefaults.standard.set([panel.frame.minX, panel.frame.minY], forKey: "companionPosition")
        manualUntil = Date().addingTimeInterval(2)
    }
    private func hide() { hiddenByUser = true; movement?.cancel(); panel.orderOut(nil); reply.hide() }
}
