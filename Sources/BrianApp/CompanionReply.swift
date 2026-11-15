import AppKit
import SwiftUI
import BrianCore

/// A separate speech bubble keeps the pet's drag area small and leaves the
/// user's current app focused. Long replies scroll instead of truncating.
@MainActor
final class CompanionReplyController {
    private let panel: NSPanel

    init() {
        panel = CompanionReplyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Brian’s reply"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(text: String, beside pet: CGRect, screen: CGRect, dismiss: @escaping () -> Void) {
        let width: CGFloat = min(300, screen.width - 24)
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: width - 52, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13)]).height
        let height = min(232, max(64, ceil(measured) + 32))
        let frame = CompanionPlacement.beside(pet, size: CGSize(width: width, height: height), screen: screen)
        panel.contentView = NSHostingView(rootView: CompanionReplyView(text: text, dismiss: dismiss)
            .frame(width: width, height: height))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func hide() { panel.orderOut(nil) }
}

private final class CompanionReplyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct CompanionReplyView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Brian’s reply")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1)))
    }
}
