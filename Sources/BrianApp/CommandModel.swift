import AppKit
import SwiftUI
import BrianCore

@MainActor
final class CommandModel: ObservableObject {
    @Published var instruction = ""
    @Published var status = "Give the local agent a task in Finder or TextEdit."
    @Published var isRunning = false
    @Published var hasError = false
    @Published var needsAccessibility = false
    @Published var isVerified = false
    @Published var focusToken = UUID()
    @Published var target: AgentApp = .textEdit
    @Published var events: [String] = []
    @Published var modelStatus = "Qwen3.5-4B · local adapter"
    private var task: Task<Void, Never>?
    private let runtime: MCPRuntime
    var onComplete: (() -> Void)?
    var onAccessibilityNeeded: (() -> Void)?

    init() {
        let bundle = ProcessInfo.processInfo.environment["BRIAN_RUNTIME_BUNDLE"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL!.appendingPathComponent("mac-control")
        let host = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("brian-runtime-host")
        runtime = MCPRuntime(executable: bundle.appendingPathComponent("mac-control"), host: host)
    }

    func submit() {
        guard !isRunning else { return }
        let text = instruction
        let app = target
        hasError = false
        isVerified = false
        needsAccessibility = false
        events = []
        isRunning = true
        task = Task { [self] in
            defer { isRunning = false; task = nil }
            do {
                if let search = try MailSearchRequest.parse(text) {
                    status = "Searching Apple Mail…"
                    try await MailSearchExecutor().execute(search)
                    try Task.checkCancellation()
                    status = "Showing Mail results for ‘\(search.query)’, newest first."
                    isVerified = true
                    instruction = ""
                    onComplete?()
                    return
                }
                // Keep instant launcher commands; everything else goes through
                // the bundled model, not the old command parser.
                do {
                    let action = try InstructionParser().parse(text)
                    status = action.label
                    try await ActionExecutor().execute(action)
                    status = "Opened. What’s next?"
                    instruction = ""
                    onComplete?()
                    return
                } catch InstructionError.unsupported { /* Agent task. */ }
                let result = try await AgentLoop(backend: runtime).run(task: text, app: app) { [weak self] event in
                    await self?.record(event)
                }
                try Task.checkCancellation()
                status = result.message
                if case .verified = result { isVerified = true }
                modelStatus = "Qwen3.5-4B + LoRA · local"
            } catch is CancellationError {
                status = "Stopped. Actions already applied remain in the app; review before continuing."
            } catch {
                if Task.isCancelled {
                    status = "Stopped. Review the app before continuing."
                } else {
                    status = error.localizedDescription
                    hasError = true
                    needsAccessibility = (error as? AgentError) == .accessibility
                    if needsAccessibility { onAccessibilityNeeded?() }
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        status = "Stopping…"
        task?.cancel()
        // MCP cancellation tears down the model's whole process group. Do not
        // allow a second task until the existing run unwinds.
    }

    func record(_ event: AgentEvent) {
        guard !Task.isCancelled else { return }
        status = event.message
        events.append(event.step == 0 ? event.message : "\(event.step). \(event.message)")
        events = Array(events.suffix(6))
    }

    func captureTarget() {
        guard !isRunning, let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let app = AgentApp.allCases.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        target = app
    }

    func shutdown() async {
        task?.cancel()
        await runtime.shutdown()
    }
}
