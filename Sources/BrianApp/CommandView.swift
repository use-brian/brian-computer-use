import SwiftUI

struct CommandView: View {
    @ObservedObject var model: CommandModel
    let dismiss: () -> Void
    @FocusState private var inputFocused: Bool
    @State private var showingFeedback = false

    private var needsAttention: Bool {
        !model.isRunning && (model.hasError || (!model.isVerified && !model.events.isEmpty))
    }

    var body: some View {
        HStack(spacing: 12) {
            BrianAvatar(mood: model.isRunning ? .working : model.isVerified ? .happy : .idle,
                        animated: model.isRunning)
                .frame(width: 28, height: 28)
            TextField("Ask Brian to do something…", text: $model.instruction)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($inputFocused)
                .onSubmit { model.submit() }
                .disabled(model.isRunning)
                .accessibilityLabel("Instruction")

            if needsAttention {
                Button { showingFeedback.toggle() } label: {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 17)).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Task needs attention")
                .help(model.status)
                .popover(isPresented: $showingFeedback) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.status).font(.callout).textSelection(.enabled)
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
            .help(model.isRunning ? "Stop" : "Send")
        }
        .padding(.horizontal, 16)
        .frame(width: 620, height: 64)
        .background { RoundedRectangle(cornerRadius: 18).fill(.regularMaterial) }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { inputFocused = true }
        .onChange(of: model.isRunning) {
            showingFeedback = false
            if !model.isRunning { inputFocused = true }
        }
        .onExitCommand { if model.isRunning { model.stop() } else { dismiss() } }
    }
}
