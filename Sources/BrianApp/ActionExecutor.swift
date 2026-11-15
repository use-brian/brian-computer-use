import AppKit
import BrianCore

@MainActor
struct ActionExecutor {
    func execute(_ action: Action) async throws {
        switch action {
        case .openURL, .searchWeb:
            guard let url = action.webURL, NSWorkspace.shared.open(url) else {
                throw ExecutionError.failedToOpen
            }
        case .openApplication(let name):
            guard let url = applicationURL(named: name) else {
                throw ExecutionError.applicationNotFound(name)
            }
            _ = try await NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    private func applicationURL(named name: String) -> URL? {
        let aliases = [
            "safari": "com.apple.Safari", "finder": "com.apple.finder",
            "notes": "com.apple.Notes", "calendar": "com.apple.iCal",
            "mail": "com.apple.mail", "terminal": "com.apple.Terminal",
            "textedit": "com.apple.TextEdit", "calculator": "com.apple.calculator",
            "chrome": "com.google.Chrome", "google chrome": "com.google.Chrome",
            "system settings": "com.apple.systempreferences",
        ]
        if let identifier = aliases[name.lowercased()],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return url
        }
        // Match installed bundles by name. User input is never executed as a path or script.
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        for root in roots {
            let apps = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil
            )) ?? []
            if let match = apps.first(where: {
                $0.pathExtension == "app" &&
                $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
            }) { return match }
        }
        return nil
    }
}

private enum ExecutionError: LocalizedError {
    case applicationNotFound(String)
    case failedToOpen

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let name): "Couldn’t find \(name). Try its name in Applications."
        case .failedToOpen: "macOS couldn’t open that address. Check your default browser."
        }
    }
}
