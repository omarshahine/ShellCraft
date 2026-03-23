import SwiftUI

/// General settings tab: shell, clipboard, behavior, and raw key-value editor.
struct GhosttyGeneralView: View {
    @Bindable var viewModel: GhosttyViewModel
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        Form {
            Section("Shell") {
                Picker("Shell Integration", selection: $viewModel.shellIntegration) {
                    Text("Detect").tag("detect")
                    Text("zsh").tag("zsh")
                    Text("Bash").tag("bash")
                    Text("Fish").tag("fish")
                    Text("None").tag("none")
                }
            }

            Section("Clipboard") {
                Picker("Clipboard Read", selection: $viewModel.clipboardRead) {
                    Text("Allow").tag("allow")
                    Text("Deny").tag("deny")
                    Text("Ask").tag("ask")
                }

                Picker("Clipboard Write", selection: $viewModel.clipboardWrite) {
                    Text("Allow").tag("allow")
                    Text("Deny").tag("deny")
                    Text("Ask").tag("ask")
                }

                Picker("Copy on Select", selection: $viewModel.copyOnSelect) {
                    Text("Off").tag("false")
                    Text("On").tag("true")
                    Text("Clipboard").tag("clipboard")
                }
            }

            Section("Behavior") {
                Toggle("Hide Mouse While Typing", isOn: $viewModel.mouseHideWhileTyping)

                Toggle("Confirm Close Surface", isOn: $viewModel.confirmCloseSurface)

                Picker("Auto Update", selection: $viewModel.autoUpdate) {
                    Text("Off").tag("off")
                    Text("Check").tag("check")
                    Text("Download").tag("download")
                }

                Picker("New Tab Position", selection: $viewModel.windowNewTabPosition) {
                    Text("Current").tag("current")
                    Text("End").tag("end")
                }
            }

            Section("Advanced") {
                ForEach(viewModel.extraEntries) { entry in
                    HStack {
                        TextField("Key", text: Binding(
                            get: { entry.key },
                            set: { viewModel.updateExtraEntry(entry, key: $0, value: entry.value) }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 200)

                        Text("=")
                            .foregroundStyle(.secondary)

                        TextField("Value", text: Binding(
                            get: { entry.value },
                            set: { viewModel.updateExtraEntry(entry, key: entry.key, value: $0) }
                        ))
                        .font(.system(.body, design: .monospaced))

                        Button(role: .destructive) {
                            viewModel.deleteExtraEntry(entry)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Key", text: $newKey)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 200)

                    Text("=")
                        .foregroundStyle(.secondary)

                    TextField("Value", text: $newValue)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        guard !newKey.trimmed.isEmpty else { return }
                        viewModel.addExtraEntry(key: newKey.trimmed, value: newValue.trimmed)
                        newKey = ""
                        newValue = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(newKey.trimmed.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}
