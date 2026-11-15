import SwiftUI
import BrianCore

struct CommandView: View {
    @ObservedObject var model: CommandModel
    let dismiss: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BrianAvatar(mood: model.isRunning ? .working : .idle, animated: false).frame(width: 30, height: 30)
                Text("Brian").font(.headline)
                Text("On your Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("⌃⌥ Space").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            HStack(spacing: 12) {
                TextField("What would you like to do?", text: $model.instruction)
                    .textFieldStyle(.plain).font(.system(size: 22))
                    .focused($inputFocused).onSubmit { model.submit() }
                    .disabled(model.isRunning).accessibilityLabel("Instruction")
                if model.isRunning {
                    Button(action: model.stop) { Image(systemName: "stop.fill").frame(width: 34, height: 34) }
                        .buttonStyle(.borderedProminent).tint(.red).accessibilityLabel("Stop agent")
                } else {
                    Button(action: model.submit) { Image(systemName: "arrow.up").font(.headline).frame(width: 34, height: 34) }
                        .buttonStyle(.borderedProminent).tint(Color(red: 0, green: 0.65, blue: 0.73))
                        .disabled(model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Run instruction")
                }
            }
            HStack {
                Picker("Work in", selection: $model.target) {
                    ForEach(AgentApp.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 185).disabled(model.isRunning)
                Spacer()
                Text(model.modelStatus).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                if model.isRunning { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout)
                    .foregroundStyle(model.hasError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if model.needsAccessibility {
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            if !model.events.isEmpty {
                DisclosureGroup("Recent steps") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in
                            Text(event).font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.font(.caption)
            } else if !model.isRunning {
                HStack(spacing: 8) {
                    ForEach(["Press the \"File\" menu.", "Open TextEdit", "Search for SwiftUI examples"], id: \.self) { example in
                        Button(example) { model.instruction = example; inputFocused = true }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            Text(model.isRunning ? "Esc stops the agent · Closing this panel keeps it running" : "Enter runs · Esc dismisses")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24).frame(width: 660).background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { inputFocused = true }
        .onChange(of: model.isRunning) { if !model.isRunning { inputFocused = true } }
        .onExitCommand { if model.isRunning { model.stop() } else { dismiss() } }
    }
}
