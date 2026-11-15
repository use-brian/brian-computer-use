import AppKit
import SwiftUI

struct PermissionGuideView: View {
    var vision = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(vision ? "Let Brian see this window" : "Let Brian use your Mac").font(.title3.bold())
            Text(vision ? "Accessibility could not reach the needed control. Allow Screen & System Audio Recording for local, single-window screenshots. Brian does not capture audio or save these images." : "Drag this app into the Accessibility list, then turn on its switch.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PermissionAppIcon().frame(width: 72, height: 72)
                .help("Drag Brian into System Settings")
            Text("Drag Brian ↑").font(.caption).foregroundStyle(.secondary)
            Button(vision ? "Open Screen Recording Settings" : "Open Accessibility Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (vision ? "Privacy_ScreenCapture" : "Privacy_Accessibility"))!)
            }
            Text("Already listed but still blocked? Remove the old Brian entry first, then drag this copy in.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("I’ve enabled it — retry", action: retry).buttonStyle(.borderedProminent)
        }
        .padding(24).frame(width: 340)
    }
}

/// Use a native file drag so Settings receives this exact installed app URL,
/// rather than a temporary item-provider copy with a different path/signature.
private struct PermissionAppIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragImageView {
        let view = AppDragImageView()
        view.image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("Brian app — drag into Accessibility settings")
        return view
    }
    func updateNSView(_ view: AppDragImageView, context: Context) {}
}

private final class AppDragImageView: NSImageView, NSDraggingSource {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
