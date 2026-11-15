import AppKit
import ApplicationServices
import BrianCore

@MainActor
final class DesktopController: DesktopTools {
    private let overlay = AgentFocusOverlay()
    private let vision = WindowVision()
    func watchTargets(_ handler: @escaping (CGRect?) -> Void) { overlay.onTarget = handler }
    private(set) var confirmationPreview: VisualTargetPreview?
    private var pendingSnapshot: VisualSnapshot?
    func finish() { overlay.hide(); vision.clear(); pendingSnapshot = nil; confirmationPreview = nil }
    let applications: [DesktopApplication]
    private var applicationURLs: [String: URL] = [:]
    private var references: [String: AXUIElement] = [:]
    private var lastObservation: DesktopObservation?
    private var processID: pid_t?
    private var windowReference: AXUIElement?
    private var observedForeground: pid_t?
    private let protectedApps: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.ScriptEditor2", "com.apple.systempreferences", "com.apple.keychainaccess"]

    init() {
        var apps: [String: String] = [:]
        var urls: [String: URL] = [:]
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            if let id = running.bundleIdentifier { apps[id] = running.localizedName ?? id; urls[id] = running.bundleURL }
        }
        for root in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            for url in (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                    urls[id] = url
                    apps[id] = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                }
            }
        }
        apps.removeValue(forKey: Bundle.main.bundleIdentifier ?? "")
        applicationURLs = urls
        applications = apps.map { DesktopApplication(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    func observe(app: String?) async throws -> DesktopObservation {
        try Task.checkCancellation()
        let snapshot = pendingSnapshot
        pendingSnapshot = nil
        references.removeAll()
        windowReference = nil
        observedForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let running = app.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            ?? NSWorkspace.shared.runningApplications.first { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        processID = running?.processIdentifier
        let identifier = running?.bundleIdentifier ?? app ?? ""
        let name = running?.localizedName ?? ""
        let trusted = AXIsProcessTrusted()
        guard trusted, let running, !protectedApps.contains(identifier) else {
            let result = DesktopObservation(app: identifier, name: name, window: protectedApps.contains(identifier) ? "Manual control required for this app" : "", accessibility: trusted, truncated: false, elements: [])
            lastObservation = result
            return result
        }
        let root = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        var rows: [DesktopElement] = []
        var visited = Set<CFHashCode>()
        var truncated = false
        var characters = 0
        var nodes = 0
        func walk(_ node: AXUIElement, depth: Int, menuPath: String = "") {
            guard depth <= 18, rows.count < 160, characters < 26000, nodes < 700 else { truncated = true; return }
            guard visited.insert(CFHash(node)).inserted else { return }
            nodes += 1
            let role = string(node, kAXRoleAttribute)
            let subrole = string(node, kAXSubroleAttribute)
            if subrole == "AXSecureTextField" { return }
            let title = string(node, kAXTitleAttribute).isEmpty ? string(node, kAXDescriptionAttribute) : string(node, kAXTitleAttribute)
            let windowLabel = ["AXCloseButton":"Close window", "AXMinimizeButton":"Minimize window", "AXZoomButton":"Zoom window"][subrole]
            let rawLabel = title.isEmpty ? (windowLabel ?? "") : title
            let label = String((menuPath + rawLabel).prefix(180))
            let value = String(string(node, kAXValueAttribute).prefix(role == kAXTextAreaRole ? 1600 : 500))
            var names: CFArray?
            AXUIElementCopyActionNames(node, &names)
            let actions = names as? [String] ?? []
            var settable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &settable)
            if !label.isEmpty || !value.isEmpty || !actions.isEmpty || settable.boolValue || role == kAXScrollAreaRole {
                let id = "e\(rows.count)"
                let row = DesktopElement(id: id, role: role, label: label, value: value,
                    enabled: attribute(node, kAXEnabledAttribute) as? Bool ?? true,
                    editable: settable.boolValue, actions: actions)
                rows.append(row); references[id] = node
                characters += label.count + value.count + 80
            }
            let path = role == kAXMenuBarItemRole ? rawLabel + " > " : menuPath
            for child in (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(160) {
                walk(child, depth: depth + 1, menuPath: path)
            }
        }
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let window = element(root, kAXFocusedWindowAttribute)
            ?? element(root, kAXMainWindowAttribute)
            ?? windows.first { attribute($0, kAXMainAttribute) as? Bool == true }
            ?? windows.first { attribute($0, kAXFocusedAttribute) as? Bool == true } ?? windows.first
        if let window {
            windowReference = window; walk(window, depth: 0)
            overlay.show(rect: frame(window), label: "Reading \(name)", vision: snapshot != nil)
        } else { overlay.hide() }
        if let menu = element(root, kAXMenuBarAttribute) { walk(menu, depth: 0) }
        let result = DesktopObservation(app: identifier, name: name,
            window: window.map { string($0, kAXTitleAttribute) } ?? "",
            accessibility: trusted, truncated: truncated, elements: rows, vision: snapshot)
        lastObservation = result
        return result
    }

    func confirmation(for action: PlannerAction, observation: DesktopObservation) -> String? {
        confirmationPreview = nil
        if action.kind == "vision_click", let capture = vision.capture,
           let point = try? VisualPoint(action.value ?? "") {
            confirmationPreview = VisualTargetPreview(image: NSImage(cgImage: capture.image, size: .zero), x: point.x, y: point.y)
            overlay.show(rect: CGRect(x: capture.frame.minX + capture.frame.width * point.x - 12,
                y: capture.frame.minY + capture.frame.height * point.y - 12, width: 24, height: 24),
                label: action.message ?? "Click", cursor: true, vision: true)
            return "Click ‘\(action.message ?? "this control")’ in \(observation.name) using vision? Review the orange target before continuing."
        }
        if action.kind == "key", ["return", "cmd+v", "cmd+s"].contains(action.value ?? "") {
            return "Use \(action.value!) in \(observation.name)? This may submit, paste, or save content."
        }
        if action.kind == "press", let target = action.target,
           let row = observation.elements.first(where: { $0.id == target }) {
            let words = row.label.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            let contextWords = Set(words + observation.window.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
            if !contextWords.isDisjoint(with: ["close", "minimize", "zoom", "send", "delete", "remove", "erase", "trash", "pay", "buy", "purchase", "publish", "submit", "install", "transfer", "share", "allow", "authorize", "confirm", "accept", "discard", "replace", "overwrite", "save"]) {
                return "Press ‘\(row.label)’ in \(observation.name)? Review the app before continuing."
            }
        }
        return nil
    }

    func execute(_ action: PlannerAction, observation: DesktopObservation) async throws -> DesktopToolResult {
        try Task.checkCancellation()
        try action.validate(observation: observation, apps: applications)
        if !action.kind.hasPrefix("vision_") { vision.clear() }
        switch action.kind {
        case "open_app":
            guard let id = action.app else { throw AgentError.invalidAction }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                running.activate(options: [])
                try await Task.sleep(for: .milliseconds(300))
                return .init(app: id, message: "Activated \(running.localizedName ?? id).")
            }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) ?? applicationURLs[id] else { throw failure("That app is not installed.") }
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            try await Task.sleep(for: .milliseconds(300))
            return .init(app: app.bundleIdentifier, message: "Opened \(app.localizedName ?? id).")
        case "open_url", "search_web":
            let actionToOpen: Action = action.kind == "open_url" ? .openURL(URL(string: action.value!)!) : .searchWeb(action.value!)
            try await ActionExecutor().execute(actionToOpen)
            try await Task.sleep(for: .milliseconds(500))
            return .init(app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                         message: "Opened the requested address/search. Inspect the browser for the result.")
        case "search_mail":
            overlay.hide()
            try await MailSearchExecutor(onTarget: { [weak self] node, label in
                guard let self else { return }
                overlay.show(rect: frame(node), label: label, cursor: true)
            }).execute(try MailSearchRequest(query: action.value!))
            return .init(app: "com.apple.mail", message: "Verified Apple Mail search for ‘\(action.value!)’ across All Mailboxes. Existing sort order is unchanged. Results are visible in Mail; message bodies have not been read by this tool.")
        case "wait":
            try await Task.sleep(for: .milliseconds(700))
            return .init(app: observation.app, message: "Waited for the interface.")
        case "observe":
            guard AXIsProcessTrusted() else { throw AgentError.accessibility }
            return .init(app: observation.app, message: "Current app controls will be available in the next observation.")
        default: break
        }
        guard AXIsProcessTrusted() else { throw AgentError.accessibility }
        guard !protectedApps.contains(observation.app), observation.app != Bundle.main.bundleIdentifier,
              observation == lastObservation, let pid = processID,
              let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == observation.app else {
            throw failure("This app needs manual control, or the observed app changed. No action was taken.")
        }
        let foreground = NSWorkspace.shared.frontmostApplication
        guard foreground?.processIdentifier == observedForeground || foreground?.processIdentifier == pid || foreground?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw failure("You switched apps while Brian was thinking. Stopped before acting.")
        }
        let root = AXUIElementCreateApplication(pid)
        if let windowReference {
            let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            guard windows.contains(where: { CFEqual($0, windowReference) }) else { throw failure("The observed window closed. Stopped before acting.") }
            if let main = element(root, kAXFocusedWindowAttribute) ?? element(root, kAXMainWindowAttribute), !CFEqual(main, windowReference) {
                throw failure("The active document changed while Brian was thinking. No action was taken.")
            }
        }
        app.activate(options: [])
        try await Task.sleep(for: .milliseconds(150))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw failure("The target app lost focus. No action was taken.") }
        if action.kind == "vision_observe" {
            overlay.show(rect: windowReference.flatMap { frame($0) }, label: "Inspecting the window", vision: true)
            pendingSnapshot = try await vision.observe(pid: pid, expectedFrame: windowReference.flatMap { frame($0) })
            return .init(app: observation.app, message: "Captured the current window because: \(action.message!). Prefer any usable Accessibility controls; use this image only for the missing parts.")
        }
        if action.kind == "vision_click" || action.kind == "vision_scroll" {
            let point = try await vision.validatedPoint(action, pid: pid, checkFrontWindow: windowReference == nil)
            overlay.show(rect: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24),
                label: action.kind == "vision_click" ? action.message! : "Scroll \(action.message!)", cursor: true, vision: true)
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw failure("You switched apps. No visual action was taken.") }
            // Revalidate after the preview as well; input is sent to the same PID.
            let currentPoint = try await vision.validatedPoint(action, pid: pid, checkFrontWindow: windowReference == nil)
            guard point == currentPoint, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw failure("The target moved or focus changed. No action was taken.") }
            if let windowReference {
                guard let focused = element(root, kAXFocusedWindowAttribute) ?? element(root, kAXMainWindowAttribute),
                      CFEqual(focused, windowReference) else { throw failure("The focused document changed. No visual action was taken.") }
            }
            if action.kind == "vision_click" {
                // Vision may reveal a target whose AX control was outside the
                // bounded tree. Prefer its semantic action whenever hit-testing
                // can identify an enabled control in this exact process.
                var hit: AXUIElement?
                if AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) == .success, let hit {
                    var hitPID: pid_t = 0
                    var names: CFArray?
                    AXUIElementGetPid(hit, &hitPID); AXUIElementCopyActionNames(hit, &names)
                    if hitPID == pid, let hitFrame = frame(hit), hitFrame.contains(point), attribute(hit, kAXEnabledAttribute) as? Bool != false,
                       let operation = (names as? [String] ?? []).first(where: { [kAXPressAction, kAXPickAction, kAXShowMenuAction].contains($0) }) {
                        let hitRole = string(hit, kAXSubroleAttribute)
                        let hitLabel = string(hit, kAXTitleAttribute).isEmpty ? string(hit, kAXDescriptionAttribute) : string(hit, kAXTitleAttribute)
                        if ["AXCloseButton", "AXMinimizeButton", "AXZoomButton"].contains(hitRole),
                           !["close", "minimize", "maximize", "zoom"].contains(where: { action.message!.lowercased().contains($0) }) {
                            throw failure("The visual point reached a window control instead of the requested target. Stopped before clicking.")
                        }
                        overlay.show(rect: hitFrame, label: "Clicking \(hitLabel.isEmpty ? action.message! : hitLabel)", cursor: true)
                        guard AXUIElementPerformAction(hit, operation as CFString) == .success else { throw failure("The visually located Accessibility action failed. Review the app before retrying.") }
                        vision.clear()
                        try await Task.sleep(for: .milliseconds(250))
                        return .init(app: observation.app, message: "Used Accessibility \(string(hit, kAXRoleAttribute)) ‘\(hitLabel)’ at the visually located point. Inspect the resulting UI; do not assume the requested task is complete.")
                    }
                }
                guard let capture = vision.capture,
                      let down = WindowPointerEvent.click(point: point, windowFrame: capture.frame, windowNumber: Int(capture.windowID), down: true),
                      let up = WindowPointerEvent.click(point: point, windowFrame: capture.frame, windowNumber: Int(capture.windowID), down: false) else { throw failure("Visual click is unavailable.") }
                down.postToPid(pid); up.postToPid(pid)
            } else {
                guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: action.message == "up" ? 420 : -420, wheel2: 0, wheel3: 0) else { throw failure("Visual scrolling is unavailable.") }
                guard let capture = vision.capture else { throw AgentError.invalidAction }
                scroll.location = point
                scroll.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(capture.windowID))
                scroll.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(capture.windowID))
                scroll.post(tap: .cgSessionEventTap)
            }
            vision.clear()
            try await Task.sleep(for: .milliseconds(300))
            return .init(app: observation.app, message: "Applied a visual \(action.kind == "vision_click" ? "click" : "scroll"). Inspect fresh Accessibility data to verify the result; this is not proof of task completion.")
        }
        if action.kind == "key" {
            let focus = element(root, kAXFocusedUIElementAttribute)
            overlay.show(rect: focus.flatMap { frame($0) } ?? windowReference.flatMap { frame($0) }, label: "Key \(action.value!)", cursor: focus != nil)
            try await Task.sleep(for: .milliseconds(300))
            try sendKey(action.value!, app: app)
            try await Task.sleep(for: .milliseconds(250))
            return .init(app: observation.app, message: "Sent \(action.value!). Completion must be checked in the next observation.")
        }
        guard let id = action.target, let node = references[id], let prior = observation.elements.first(where: { $0.id == id }),
              string(node, kAXRoleAttribute) == prior.role,
              String(string(node, kAXValueAttribute).prefix(prior.role == kAXTextAreaRole ? 1600 : 500)) == prior.value,
              attribute(node, kAXEnabledAttribute) as? Bool != false else { throw failure("The target changed while Brian was thinking. No action was taken.") }
        // Labels are checked separately from the menu path added to model context.
        let label = string(node, kAXTitleAttribute).isEmpty ? string(node, kAXDescriptionAttribute) : string(node, kAXTitleAttribute)
        guard prior.label.hasSuffix(String(label.prefix(180))) || prior.label == String(label.prefix(180)) else {
            throw failure("The target label changed. No action was taken.")
        }
        overlay.show(rect: frame(node), label: "\(action.kind == "set_text" ? "Typing in" : action.kind == "scroll" ? "Scrolling" : "Clicking") \(prior.label.isEmpty ? prior.role : prior.label)", cursor: true)
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw failure("You switched apps before the action. Stopped.") }
        switch action.kind {
        case "press":
            var names: CFArray?
            AXUIElementCopyActionNames(node, &names)
            guard let operation = (names as? [String] ?? []).first(where: { [kAXPressAction, kAXPickAction, kAXShowMenuAction].contains($0) }),
                  AXUIElementPerformAction(node, operation as CFString) == .success else { throw failure("That control could not be pressed.") }
        case "set_text":
            let text = action.value!
            guard AXUIElementSetAttributeValue(node, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
                  let focused = element(root, kAXFocusedUIElementAttribute), CFEqual(focused, node) else { throw failure("Could not focus the intended text field.") }
            if AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, text as CFString) != .success || string(node, kAXValueAttribute) != text {
                // Native text controls sometimes expose setters but require keys.
                try sendKey("cmd+a", app: app)
                try sendKeyCode(51, flags: [], app: app)
                for character in text {
                    try Task.checkCancellation()
                    guard let focus = element(root, kAXFocusedUIElementAttribute), CFEqual(focus, node) else { throw failure("Text focus changed. Stopped; review any partial edit.") }
                    if character == "\n" { try sendKeyCode(36, flags: [], app: app); continue }
                    let units = Array(String(character).utf16)
                    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                          let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { throw failure("Text input is unavailable.") }
                    units.withUnsafeBufferPointer { buffer in
                        down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                        up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                    }
                    down.postToPid(pid); up.postToPid(pid)
                    try await Task.sleep(for: .milliseconds(4))
                }
            }
            try await Task.sleep(for: .milliseconds(200))
            guard string(node, kAXValueAttribute) == text else { throw failure("Text readback did not match. Review the app before retrying.") }
            return .init(app: observation.app, message: "Verified exact text in \(prior.label.isEmpty ? prior.role : prior.label).")
        case "scroll":
            let operation = action.value == "up" ? "AXScrollUpByPage" : "AXScrollDownByPage"
            var supported: CFArray?
            AXUIElementCopyActionNames(node, &supported)
            guard (supported as? [String] ?? []).contains(operation) else {
                throw DesktopRecoveryError.accessibilityUnavailable("This scroll area does not expose accessible page scrolling. No scroll was dispatched.")
            }
            guard AXUIElementPerformAction(node, operation as CFString) == .success else { throw failure("Accessible scrolling failed. Review the app before retrying.") }
        default: throw AgentError.invalidAction
        }
        try await Task.sleep(for: .milliseconds(250))
        return .init(app: observation.app, message: "Applied \(action.kind) to \(prior.label.isEmpty ? prior.role : prior.label); checking the resulting UI next.")
    }

    private func sendKey(_ key: String, app: NSRunningApplication) throws {
        let map: [String: CGKeyCode] = ["return":36, "tab":48, "escape":53, "cmd+n":45, "cmd+f":3, "cmd+a":0, "cmd+c":8, "cmd+v":9, "cmd+z":6, "cmd+s":1, "left":123, "right":124, "up":126, "down":125]
        guard let code = map[key] else { throw AgentError.invalidAction }
        try sendKeyCode(code, flags: key.hasPrefix("cmd+") ? .maskCommand : [], app: app)
    }
    private func sendKeyCode(_ code: CGKeyCode, flags: CGEventFlags, app: NSRunningApplication) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { throw failure("The target app lost keyboard focus.") }
        down.flags = flags; up.flags = flags
        down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
    }
    private func frame(_ node: AXUIElement) -> CGRect? {
        guard let position = attribute(node, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(node, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
    private func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func string(_ node: AXUIElement, _ name: String) -> String {
        guard let value = attribute(node, name) else { return "" }
        if let text = value as? String { return text }
        if let text = value as? NSAttributedString { return text.string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
    private func failure(_ message: String) -> AgentError { .runtime(message) }
}
