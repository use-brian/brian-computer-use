// Harmless local fixture for goal completion across selection + content inspection.
import AppKit

@MainActor final class WorkflowDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow!
    let table = NSTableView()
    let body = NSTextView()
    let labels = ["ExampleAir QX100 — booking confirmation", "ExampleAir QX200 — booking confirmation"]
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit Brian Workflow Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; NSApp.mainMenu = menu
        window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 820, height: 480), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Brian Workflow Test"
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 820, height: 480))
        let heading = NSTextField(labelWithString: "Bookings — select each confirmation to inspect its departure date")
        heading.frame = CGRect(x: 20, y: 440, width: 780, height: 24); root.addSubview(heading)
        let column = NSTableColumn(identifier: .init("booking")); column.title = "Booking confirmations"; column.width = 320
        table.addTableColumn(column); table.rowHeight = 44; table.delegate = self; table.dataSource = self
        table.setAccessibilityLabel("Booking confirmations")
        let list = NSScrollView(frame: CGRect(x: 20, y: 20, width: 330, height: 400))
        list.documentView = table; list.hasVerticalScroller = true; root.addSubview(list)
        let content = NSScrollView(frame: CGRect(x: 370, y: 20, width: 430, height: 400))
        body.isEditable = false; body.isSelectable = true; body.font = .systemFont(ofSize: 17)
        body.textContainerInset = CGSize(width: 12, height: 12)
        body.setAccessibilityLabel("Booking details")
        body.string = "Select a booking to read its departure date and flight details. The dates are not shown in the list."
        content.documentView = body; content.hasVerticalScroller = true; root.addSubview(content)
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { labels.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: labels[row])
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard labels.indices.contains(table.selectedRow) else { return }
        let index = table.selectedRow
        let date = Calendar.current.date(byAdding: .day, value: index == 0 ? -2 : 1, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        body.string = "Booking confirmation\n\nAirline: ExampleAir\nFlight: \(index == 0 ? "QX100" : "QX200")\nDeparture date: \(formatter.string(from: date))\nDeparture time: \(index == 0 ? "08:10" : "14:20") local time\nRoute: Singapore to Tokyo\n\nThis is synthetic test data."
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main enum WorkflowDemo {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = WorkflowDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
