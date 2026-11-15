import SwiftUI
import BrianCore

@MainActor
final class CommandModel: ObservableObject {
    @Published var instruction = ""
    @Published var status = "Open an app, visit a website, or search the web."
    @Published var isRunning = false
    @Published var hasError = false
    @Published var focusToken = UUID()
    var onComplete: (() -> Void)?

    func submit() {
        guard !isRunning else { return }
        do {
            let action = try InstructionParser().parse(instruction)
            hasError = false
            isRunning = true
            status = action.label
            Task {
                do {
                    try await ActionExecutor().execute(action)
                    status = "Opened. What’s next?"
                    instruction = ""
                    isRunning = false
                    onComplete?()
                } catch {
                    status = error.localizedDescription
                    hasError = true
                    isRunning = false
                }
            }
        } catch {
            status = error.localizedDescription
            hasError = true
        }
    }
}

struct CommandView: View {
    @ObservedObject var model: CommandModel
    let dismiss: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "command.square.fill")
                    .font(.title2).foregroundStyle(.orange)
                Text("Brian").font(.headline)
                Spacer()
                Text("⌃⌥ Space").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            HStack(spacing: 12) {
                TextField("What would you like to do?", text: $model.instruction)
                    .textFieldStyle(.plain).font(.system(size: 23))
                    .focused($inputFocused)
                    .onSubmit { model.submit() }
                    .disabled(model.isRunning)
                    .accessibilityLabel("Instruction")
                Button(action: model.submit) {
                    Image(systemName: "arrow.up").font(.headline)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(model.isRunning || model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Run instruction")
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                if model.isRunning { ProgressView().controlSize(.small) }
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(model.hasError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("↵ Run").font(.caption).foregroundStyle(.tertiary)
            }
            if !model.isRunning {
                HStack(spacing: 8) {
                    ForEach(["Open Notes", "Open github.com", "Search for coffee nearby"], id: \.self) { example in
                        Button(example) {
                            model.instruction = example
                            inputFocused = true
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { inputFocused = true }
        .onChange(of: model.isRunning) { if !model.isRunning { inputFocused = true } }
        .onExitCommand(perform: dismiss)
    }
}
