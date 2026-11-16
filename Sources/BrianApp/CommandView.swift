import SwiftUI

struct CommandView: View {
    @ObservedObject var model: CommandModel
    let dismiss: () -> Void
    @FocusState private var inputFocused: Bool
    @State private var showingFeedback = false

    private var needsAttention: Bool {
        model.pendingConfirmation != nil || (!model.isRunning && (model.hasError || model.hasResponse))
    }

    var body: some View {
        HStack(spacing: 12) {
            BrianAvatar(mood: model.isRunning ? .working : model.isFinished ? .happy : .idle,
                        animated: model.isRunning)
                .frame(width: 28, height: 28)
            if model.isRunning, !model.targetLabel.isEmpty {
                Text(model.targetLabel).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 80)
                    .accessibilityLabel("Working in " + model.targetLabel)
            }
            if model.isRunning {
                Text(model.pendingConfirmation == nil ? model.status : "Waiting for your confirmation…")
                    .font(.system(size: 18)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Current action")
            } else {
            TextField("Ask Brian to do something…", text: $model.instruction)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($inputFocused)
                .onSubmit { model.submit() }
                .disabled(model.isRunning)
                .accessibilityLabel("Instruction")
            }

            if needsAttention {
                Button { showingFeedback.toggle() } label: {
                    Image(systemName: model.hasError || model.pendingConfirmation != nil ? "exclamationmark.circle" : "text.bubble")
                        .font(.system(size: 17)).foregroundStyle(model.hasError || model.pendingConfirmation != nil ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.pendingConfirmation != nil ? "Confirm action" : model.hasError ? "Task needs attention" : "Brian’s reply")
                .help(model.status)
                .popover(isPresented: $showingFeedback) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.pendingConfirmation ?? model.status).font(.callout).textSelection(.enabled)
                        if let preview = model.confirmationPreview { VisualTargetPreviewView(preview: preview) }
                        if model.pendingConfirmation != nil {
                            HStack {
                                Button("Cancel") { model.resolveApproval(false) }
                                Button("Continue") { model.resolveApproval(true) }.buttonStyle(.borderedProminent)
                            }
                        }
                        if model.needsScreenRecording {
                            Button("Enable vision access") { model.onScreenRecordingNeeded?() }
                        }
                        if model.needsAccessibility {
                            Button("Set up access") { model.onAccessibilityNeeded?() }
                        }
                    }
                    .padding(16).frame(width: 320, alignment: .leading)
                }
            }

            Button {
                if model.isRunning { model.stop() } else { model.submit() }
            } label: {
                Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background { RoundedRectangle(cornerRadius: 10).fill(Color(red: 0, green: 0.65, blue: 0.73)) }
            }
            .buttonStyle(.plain)
            .disabled(!model.isRunning && model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(!model.isRunning && model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel(model.isRunning ? "Stop agent" : "Run instruction")
            .help(model.isRunning ? model.status + " Click to stop." : "Send")
        }
        .padding(.horizontal, 16)
        .frame(width: 620, height: 64)
        .background { RoundedRectangle(cornerRadius: 18).fill(.regularMaterial) }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { inputFocused = true }
        .onChange(of: model.isRunning) {
            if model.isRunning { showingFeedback = false }
            if !model.isRunning { inputFocused = true }
        }
        .onChange(of: model.responseVersion) { showingFeedback = false }
        .onChange(of: model.pendingConfirmation) { showingFeedback = model.pendingConfirmation != nil }
        .onExitCommand { if model.isRunning { model.stop() } else { dismiss() } }
    }
}

struct VisualTargetPreview {
    let image: NSImage
    let x: Double
    let y: Double
}

private struct VisualTargetPreviewView: View {
    let preview: VisualTargetPreview
    var body: some View {
        let aspect = preview.image.size.width / max(1, preview.image.size.height)
        let width = min(288, 190 * aspect)
        let height = width / aspect
        ZStack(alignment: .topLeading) {
            Image(nsImage: preview.image).resizable().frame(width: width, height: height)
            Circle().stroke(.orange, lineWidth: 3).background(Circle().fill(.white.opacity(0.3)))
                .frame(width: 16, height: 16).position(x: width * preview.x, y: height * preview.y)
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Captured window with proposed click target marked in orange")
    }
}
