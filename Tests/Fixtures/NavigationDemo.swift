// Manual integration fixture. Compile with swiftc -parse-as-library -framework AppKit.
import AppKit

@MainActor final class DemoCanvas: NSView {
    var completed = false
    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
        (completed ? "Vision click confirmed" : "Custom canvas: choose Continue" as NSString).draw(at: CGPoint(x: 40, y: 70), withAttributes: attrs)
        NSColor.systemGray.setFill(); NSBezierPath(roundedRect: CGRect(x: 60, y: 280, width: 240, height: 90), xRadius: 12, yRadius: 12).fill()
        NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: CGRect(x: 500, y: 280, width: 240, height: 90), xRadius: 12, yRadius: 12).fill()
        let button: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.white]
        ("Cancel" as NSString).draw(at: CGPoint(x: 130, y: 305), withAttributes: button)
        ("Continue" as NSString).draw(at: CGPoint(x: 560, y: 305), withAttributes: button)
    }
    override func mouseDown(with event: NSEvent) {
        if CGRect(x: 500, y: 280, width: 240, height: 90).contains(convert(event.locationInWindow, from: nil)) {
            completed = true; needsDisplay = true; window?.title = "Brian Navigation Test — Vision click confirmed"
        }
    }
}
@MainActor final class DemoWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let p = event.locationInWindow
            let values: [String: CGFloat] = ["x":p.x, "y":p.y, "window":CGFloat(windowNumber),
                "width":frame.width, "height":frame.height, "originX":frame.minX, "originY":frame.minY,
                "screenTop":NSScreen.screens.first?.frame.maxY ?? 0,
                "cgX":event.cgEvent?.location.x ?? 0, "cgY":event.cgEvent?.location.y ?? 0]
            if let data = try? JSONSerialization.data(withJSONObject: values) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/brian-navigation-pointer.json"), options: .atomic)
            }
        }
        super.sendEvent(event)
        if event.type == .leftMouseDown && !title.contains("Vision click confirmed") {
            let p = event.locationInWindow
            title = "Brian Navigation Test — pointer \(Int(p.x)),\(Int(p.y)); frame \(Int(frame.width))×\(Int(frame.height))"
        }
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = DemoWindow(contentRect: CGRect(x: 200, y: 200, width: 800, height: 460), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Brian Navigation Test"
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 460))
        let canvas = DemoCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 400)); root.addSubview(canvas)
        let button = NSButton(title: "Accessibility check", target: self, action: #selector(checked))
        button.frame = CGRect(x: 40, y: 415, width: 220, height: 30); root.addSubview(button)
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func checked() { window.title = "Brian Navigation Test — Accessibility click confirmed" }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main enum NavigationDemo {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
