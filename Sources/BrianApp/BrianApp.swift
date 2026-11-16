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
        // Accessory apps do not get SwiftUI's default Edit menu. Install the
        // responder-chain equivalents used by native text fields explicitly.
        let mainMenu = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "Brian")
        applicationMenu.addItem(withTitle: "Quit Brian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = applicationMenu; mainMenu.addItem(application)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let redo = editMenu.insertItem(withTitle: "Redo", action: Selector("redo:"), keyEquivalent: "z", at: 1)
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.submenu = editMenu; mainMenu.addItem(edit)
        app.mainMenu = mainMenu
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: CommandPanel!
    private var statusItem: NSStatusItem!
    private var shortcut: GlobalShortcut!
    private var companion: CompanionController!
    private var permissionPanel: NSPanel?
    private let model = CommandModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let icon = Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("Brian.icns")) }
        if let icon { NSApp.applicationIconImage = icon }
        panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 64),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Brian"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CommandView(model: model) { [weak self] in
            self?.hidePanel()
        })
        model.onComplete = { [weak self] in self?.hidePanel() }
        model.onScreenRecordingNeeded = { [weak self] in self?.showPermissionGuide(vision: true) }
        model.onAccessibilityNeeded = { [weak self] in self?.showPermissionGuide() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menuIcon = (icon?.copy() as? NSImage) ?? NSImage(systemSymbolName: "command.square", accessibilityDescription: "Brian")
        menuIcon?.size = NSSize(width: 19, height: 19)
        statusItem.button?.image = menuIcon
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Brian", action: #selector(showPanel), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let showPet = NSMenuItem(title: "Show Brian companion", action: #selector(showCompanion), keyEquivalent: "")
        showPet.target = self
        menu.addItem(showPet)
        let newTask = NSMenuItem(title: "New conversation", action: #selector(newConversation), keyEquivalent: "")
        newTask.target = self
        menu.addItem(newTask)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Brian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        companion = CompanionController(model: model) { [weak self] in self?.showPanel() }
        companion.show()

        shortcut = GlobalShortcut { [weak self] in
            guard let self else { return }
            if panel.isVisible && panel.isKeyWindow { hidePanel() }
            else { showPanel() }
        }
        if !shortcut.register() {
            model.status = "Shortcut unavailable. Open Brian from the menu bar; ⌃⌥Space may be in use."
            model.hasError = true
        }
        showPanel()
    }

    @objc private func showPanel() {
        model.captureTarget()
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
        companion?.runToBar(panel.frame)
    }

    private func hidePanel() {
        panel.orderOut(nil)
        companion?.barClosed()
    }

    @objc private func showCompanion() { companion.show() }

    private func showPermissionGuide(vision: Bool = false) {
        permissionPanel?.close()
        do {
            let guide = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 388, height: 330),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            guide.title = "Allow Brian"
            guide.isReleasedWhenClosed = false
            guide.hidesOnDeactivate = false
            guide.level = .floating
            guide.contentView = NSHostingView(rootView: PermissionGuideView(vision: vision) { [weak self] in
                guard let self else { return }
                permissionPanel?.orderOut(nil)
                model.submit()
            })
            guide.center()
            permissionPanel = guide
        }
        permissionPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func newConversation() { model.newTask(); showPanel() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shortcut.unregister()
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
