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
    let move: (CGSize, Bool) -> Void
    let hide: () -> Void
    @State private var hovering = false

    private var mood: BrianMood {
        model.isRunning ? .working : model.hasError ? .attention : model.isVerified ? .happy : .idle
    }
    private var label: String {
        model.isRunning ? "Working…" : model.hasError ? "Needs you" : model.isVerified ? "Done!" : "Hey, I’m Brian"
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
            HStack(spacing: 4) {
                Circle().fill(model.hasError ? .orange : Color.cyan).frame(width: 4, height: 4)
                Text("Brian").font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.primary).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
        }
        .frame(width: 146, height: 158)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .gesture(DragGesture(minimumDistance: 5)
            .onChanged { move($0.translation, false) }
            .onEnded { move($0.translation, true) })
        .contextMenu {
            Button("Open Brian", action: open)
            if model.isRunning { Button("Stop task", action: model.stop) }
            Button("Hide companion", action: hide)
        }
        .help("Click to give Brian a task. Drag to move. Right-click for options.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brian companion")
        .accessibilityValue(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}

@MainActor
final class CompanionController {
    private let panel: NSPanel
    private var dragOrigin: CGPoint?

    init(model: CommandModel, open: @escaping () -> Void) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 146, height: 158),
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
            move: { [weak self] translation, done in self?.move(translation, done: done) },
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

    private func move(_ translation: CGSize, done: Bool) {
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        let origin = dragOrigin!
        let position = CGPoint(x: origin.x + translation.width, y: origin.y - translation.height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.visibleFrame
            ?? NSScreen.main!.visibleFrame
        panel.setFrameOrigin(clamp(position, to: screen))
        if done {
            UserDefaults.standard.set([panel.frame.minX, panel.frame.minY], forKey: "companionPosition")
            dragOrigin = nil
        }
    }

    private func clamp(_ point: CGPoint, to screen: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, screen.minX), screen.maxX - panel.frame.width),
                y: min(max(point.y, screen.minY), screen.maxY - panel.frame.height))
    }
}
