import AppKit
import SwiftUI

@main
enum BrianApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: CommandPanel!
    private var statusItem: NSStatusItem!
    private var shortcut: GlobalShortcut!
    private let model = CommandModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 668, height: 245),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Brian"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CommandView(model: model) { [weak self] in
            self?.panel.orderOut(nil)
        })
        model.onComplete = { [weak self] in self?.panel.orderOut(nil) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Brian")
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Brian", action: #selector(showPanel), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Brian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        shortcut = GlobalShortcut { [weak self] in
            guard let self else { return }
            if panel.isVisible && panel.isKeyWindow { panel.orderOut(nil) }
            else { showPanel() }
        }
        if !shortcut.register() {
            model.status = "Shortcut unavailable. Open Brian from the menu bar; ⌃⌥Space may be in use."
            model.hasError = true
        }
        showPanel()
    }

    @objc private func showPanel() {
        // Place on the screen under the pointer, including multi-monitor setups.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.minY + frame.height * 0.63 - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusToken = UUID()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { shortcut.unregister() }
}

private final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
