import SwiftUI

struct PermissionEditorSheet: View {
    let mode: Mode
    let onSave: (String, ClaudePermission.PermissionList) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String
    @State private var list: ClaudePermission.PermissionList

    enum Mode {
        case add
        case edit(ClaudePermission)

        var title: String {
            switch self {
            case .add: "Add Permission"
            case .edit: "Edit Permission"
            }
        }
    }

    init(mode: Mode, onSave: @escaping (String, ClaudePermission.PermissionList) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .add:
            _pattern = State(initialValue: "")
            _list = State(initialValue: .allow)
        case .edit(let permission):
            _pattern = State(initialValue: permission.pattern)
            _list = State(initialValue: permission.list)
        }
    }

    private var inferredCategory: PermissionCategory {
        PermissionCategory.infer(from: pattern)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern") {
                    TextField("e.g., Bash(git *), Read(*), mcp__*", text: $pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Use wildcards (*) to match tool calls. Examples: Bash(git *), Read(~/Projects/*)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("List") {
                    Picker("Permission List", selection: $list) {
                        ForEach(ClaudePermission.PermissionList.allCases) { option in
                            HStack {
                                Image(systemName: option == .allow ? "checkmark.shield" : "xmark.shield")
                                Text(option.displayName)
                            }
                            .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Inferred Category") {
                    HStack {
                        Text(inferredCategory.rawValue)
                            .font(.callout)

                        Spacer()

                        Text(inferredCategory.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.15))
                            .foregroundStyle(categoryColor)
                            .clipShape(Capsule())
                    }

                    Text("Category is automatically inferred from the pattern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(pattern.trimmed, list)
                        dismiss()
                    }
                    .disabled(pattern.trimmed.isEmpty)
                }
            }
        }
        .frame(width: 480, height: 380)
    }

    private var categoryColor: Color {
        switch inferredCategory {
        case .bash: .blue
        case .git: .orange
        case .buildTools: .purple
        case .fileAccess: .green
        case .webAccess: .cyan
        case .mcpTools: .indigo
        case .skills: .pink
        case .other: .gray
        }
    }
}
