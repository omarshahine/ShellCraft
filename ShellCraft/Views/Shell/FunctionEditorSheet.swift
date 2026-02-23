import SwiftUI

struct FunctionEditorSheet: View {
    let function: ShellFunction?
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var functionBody: String
    @State private var description: String
    @State private var validationError: String? = nil

    private var isEditing: Bool { function != nil }

    init(function: ShellFunction?, onSave: @escaping (String, String, String) -> Void) {
        self.function = function
        self.onSave = onSave
        _name = State(initialValue: function?.name ?? "")
        _functionBody = State(initialValue: function?.body ?? "")
        _description = State(initialValue: function?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
            Section {
                TextField("Function Name", text: $name)
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
            } footer: {
                Text("Must start with a letter or underscore. Can contain letters, digits, underscores, and hyphens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Brief description (optional)", text: $description)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Description")
            } footer: {
                Text("Added as a comment above the function definition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                CodeEditorView(
                    text: $functionBody,
                    language: "bash",
                    lineNumbers: true,
                    isEditable: true
                )
                .frame(minHeight: 200)
            } header: {
                Text("Function Body")
            }

            // Preview
            Section {
                Text(previewText)
                    .fontDesign(.monospaced)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isEditing ? "Edit Function" : "New Function")
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
        .frame(width: 600, height: 560)
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmed.isEmpty && !functionBody.trimmed.isEmpty && isValidFunctionName(name.trimmed)
    }

    private func isValidFunctionName(_ name: String) -> Bool {
        let pattern = /^[a-zA-Z_][\w-]*$/
        return name.wholeMatch(of: pattern) != nil
    }

    private func attemptSave() {
        let trimmedName = name.trimmed

        if trimmedName.isEmpty {
            validationError = "Function name cannot be empty."
            return
        }

        if !isValidFunctionName(trimmedName) {
            validationError = "Invalid function name. Must start with a letter or underscore."
            return
        }

        if functionBody.trimmed.isEmpty {
            validationError = "Function body cannot be empty."
            return
        }

        validationError = nil
        onSave(trimmedName, functionBody, description.trimmed)
        dismiss()
    }

    // MARK: - Preview

    private var previewText: String {
        let safeName = name.trimmed.isEmpty ? "myfunction" : name.trimmed
        let safeBody = functionBody.trimmed.isEmpty ? "  echo \"hello\"" : functionBody
        var lines: [String] = []
        if !description.trimmed.isEmpty {
            lines.append("# \(description.trimmed)")
        }
        lines.append("\(safeName)() {")
        for line in safeBody.components(separatedBy: "\n") {
            lines.append("  \(line)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
