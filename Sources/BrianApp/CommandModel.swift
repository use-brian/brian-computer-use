import AppKit
import SwiftUI
import BrianCore

@MainActor
final class CommandModel: ObservableObject {
    @Published var windows: [SelectedWindow] = []
    @Published var selectedWindowID: UUID?
    var selectedWindow: SelectedWindow? { windows.first { $0.id == selectedWindowID } }
    var targetLabel: String { selectedWindow?.name ?? "Mac" }
    @Published var activityTarget: CGRect?
    @Published var instruction = ""
    @Published var status = ""
    @Published var isRunning = false
    @Published var hasError = false
    @Published var needsAccessibility = false
    @Published var needsScreenRecording = false
    @Published var isFinished = false
    @Published var hasResponse = false
    @Published var responseVersion = 0
    @Published var confirmationPreview: VisualTargetPreview?
    @Published var pendingConfirmation: String?
    @Published var focusToken = UUID()
    private var task: Task<Void, Never>?
    private var approval: CheckedContinuation<Bool, Never>?
    private let runtime: MCPRuntime
    private let desktop = DesktopController()
    private var conversation: [ConversationTurn] = []
    private var foregroundApp: String?
    var onComplete: (() -> Void)?
    var onScreenRecordingNeeded: (() -> Void)?
    var onAccessibilityNeeded: (() -> Void)?

    init() {
        let bundle = ProcessInfo.processInfo.environment["BRIAN_RUNTIME_BUNDLE"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL!.appendingPathComponent("mac-control")
        let host = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("brian-runtime-host")
        runtime = MCPRuntime(executable: bundle.appendingPathComponent("mac-control"), host: host)
        desktop.watchTargets { [weak self] rect in self?.activityTarget = rect }
    }

    func submit() {
        guard !isRunning else { return }
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        hasError = false; isFinished = false; hasResponse = false; needsAccessibility = false; needsScreenRecording = false
        isRunning = true
        task = Task { [self] in
            defer { desktop.finish(); isRunning = false; task = nil }
            do {
                let window = selectedWindow
                desktop.bind(window)
                let result = try await NaturalAgent(planner: runtime, tools: desktop).run(
                    task: text, app: window?.app ?? foregroundApp, conversation: conversation, scope: window?.scope,
                    approve: { [weak self] reason in await self?.requestApproval(reason) ?? false },
                    onEvent: { [weak self] message in self?.status = message })
                try Task.checkCancellation()
                status = result.message
                isFinished = !result.needsInput && result.steps > 0
                hasResponse = true
                conversation += [ConversationTurn(role: "user", content: text), ConversationTurn(role: "assistant", content: result.message)]
                conversation = Array(conversation.suffix(6))
                instruction = ""
                responseVersion += 1
            } catch is CancellationError {
                status = "Stopped. Review any actions already applied."
                hasResponse = true; responseVersion += 1
            } catch {
                if Task.isCancelled {
                    status = "Stopped. Review the app before continuing."
                } else {
                    status = error.localizedDescription
                    hasError = true
                    needsAccessibility = (error as? AgentError) == .accessibility
                    needsScreenRecording = (error as? AgentError) == .screenRecording
                    if needsScreenRecording { onScreenRecordingNeeded?() }
                    if needsAccessibility { onAccessibilityNeeded?() }
                }
                hasResponse = true; responseVersion += 1
                conversation += [ConversationTurn(role: "user", content: text), ConversationTurn(role: "assistant", content: status)]
                conversation = Array(conversation.suffix(6))
            }
            if let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               active != Bundle.main.bundleIdentifier { foregroundApp = active }
        }
    }

    private func requestApproval(_ reason: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        confirmationPreview = desktop.confirmationPreview
        pendingConfirmation = reason
        return await withCheckedContinuation { approval = $0 }
    }
    func resolveApproval(_ allow: Bool) {
        let waiting = approval
        approval = nil; pendingConfirmation = nil; confirmationPreview = nil
        waiting?.resume(returning: allow)
    }
    func stop() {
        guard isRunning else { return }
        desktop.finish()
        status = "Stopping…"
        task?.cancel()
        resolveApproval(false)
    }
    func captureTarget() {
        guard !isRunning, let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        foregroundApp = id
        let previous = selectedWindow
        windows = desktop.availableWindows()
        if let previous {
            if let match = windows.first(where: { $0.pid == previous.pid && CFEqual($0.window, previous.window) }) {
                selectedWindowID = match.id
            } else {
                windows.append(previous); selectedWindowID = previous.id
            }
        }
    }
    func newTask() {
        guard !isRunning else { return }
        conversation = []; foregroundApp = nil; instruction = ""; status = ""; hasResponse = false; hasError = false; isFinished = false
    }
    func shutdown() async {
        task?.cancel(); resolveApproval(false)
        await runtime.shutdown()
    }
}
