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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
            self?.panel.orderOut(nil)
        })
        model.onComplete = { [weak self] in self?.panel.orderOut(nil) }
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
        let targetMenu = NSMenu()
        for (index, title) in ["Finder", "TextEdit"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(selectTarget(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            targetMenu.addItem(item)
        }
        let targetItem = NSMenuItem(title: "Work in", action: nil, keyEquivalent: "")
        targetItem.submenu = targetMenu
        menu.addItem(targetItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Brian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        companion = CompanionController(model: model) { [weak self] in self?.showPanel() }
        companion.show()

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
    }

    @objc private func showCompanion() { companion.show() }

    private func showPermissionGuide() {
        if permissionPanel == nil {
            let guide = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 388, height: 330),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            guide.title = "Allow Brian"
            guide.isReleasedWhenClosed = false
            guide.hidesOnDeactivate = false
            guide.level = .floating
            guide.contentView = NSHostingView(rootView: PermissionGuideView { [weak self] in
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

    @objc private func selectTarget(_ sender: NSMenuItem) {
        guard !model.isRunning else { return }
        model.target = sender.tag == 0 ? .finder : .textEdit
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectTarget(_:)) {
            menuItem.state = model.target == (menuItem.tag == 0 ? .finder : .textEdit) ? .on : .off
            return !model.isRunning
        }
        return true
    }

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
