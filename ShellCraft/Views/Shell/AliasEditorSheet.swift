import SwiftUI

struct AliasEditorSheet: View {
    let alias: ShellAlias?
    let onSave: (String, String, AliasCategory, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var expansion: String
    @State private var category: AliasCategory
    @State private var isEnabled: Bool
    @State private var validationError: String? = nil

    private var isEditing: Bool { alias != nil }

    init(alias: ShellAlias?, onSave: @escaping (String, String, AliasCategory, Bool) -> Void) {
        self.alias = alias
        self.onSave = onSave
        _name = State(initialValue: alias?.name ?? "")
        _expansion = State(initialValue: alias?.expansion ?? "")
        _category = State(initialValue: alias?.category ?? .general)
        _isEnabled = State(initialValue: alias?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Alias Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, _ in
                            validationError = nil
                        }

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("Command or expansion", text: $expansion, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .lineLimit(1...5)
                        .autocorrectionDisabled()
                } header: {
                    Text("Expansion")
                } footer: {
                    Text("The command that runs when you type the alias name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(AliasCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Category")
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                } footer: {
                    Text("Disabled aliases are commented out with # in the config file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Preview
                Section {
                    Text(previewLine)
                        .fontDesign(.monospaced)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Preview")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Alias" : "New Alias")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        attemptSave()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 480, height: 440)
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmed.isEmpty && !expansion.trimmed.isEmpty && !name.contains(" ")
    }

    private func attemptSave() {
        let trimmedName = name.trimmed

        if trimmedName.isEmpty {
            validationError = "Alias name cannot be empty."
            return
        }

        if trimmedName.contains(" ") {
            validationError = "Alias name cannot contain spaces."
            return
        }

        if trimmedName.contains("=") {
            validationError = "Alias name cannot contain '='."
            return
        }

        if expansion.trimmed.isEmpty {
            validationError = "Expansion cannot be empty."
            return
        }

        validationError = nil

        // Auto-infer category if still general and user didn't change it
        var finalCategory = category
        if category == .general {
            finalCategory = AliasCategory.infer(from: trimmedName, expansion: expansion.trimmed)
        }

        onSave(trimmedName, expansion.trimmed, finalCategory, isEnabled)
        dismiss()
    }

    // MARK: - Preview

    private var previewLine: String {
        let prefix = isEnabled ? "" : "# "
        let safeName = name.trimmed.isEmpty ? "myalias" : name.trimmed
        let safeExpansion = expansion.trimmed.isEmpty ? "command" : expansion.trimmed
        if safeExpansion.contains("'") {
            return "\(prefix)alias \(safeName)=\"\(safeExpansion)\""
        }
        return "\(prefix)alias \(safeName)='\(safeExpansion)'"
    }
}
