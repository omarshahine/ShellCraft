import SwiftUI

struct EnvVarEditorSheet: View {
    let variable: EnvironmentVariable?
    let onSave: (String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var key: String
    @State private var value: String
    @State private var isKeychain: Bool
    @State private var keychainServiceName: String
    @State private var validationError: String? = nil

    private var isEditing: Bool { variable != nil }

    init(variable: EnvironmentVariable?, onSave: @escaping (String, String, Bool) -> Void) {
        self.variable = variable
        self.onSave = onSave
        _key = State(initialValue: variable?.key ?? "")
        _value = State(initialValue: variable?.value ?? "")
        _isKeychain = State(initialValue: variable?.isKeychainDerived ?? false)
        _keychainServiceName = State(initialValue: variable.map { "env/\($0.key)" } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("VARIABLE_NAME", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .autocorrectionDisabled()
                        .textCase(.uppercase)
                        .onChange(of: key) { _, newValue in
                            validationError = nil
                            // Auto-generate keychain service name
                            if keychainServiceName.isEmpty || keychainServiceName == "env/\(key)" {
                                keychainServiceName = "env/\(newValue)"
                            }
                        }

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Variable Name")
                } footer: {
                    Text("Must contain only letters, digits, and underscores. Convention: UPPER_SNAKE_CASE.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Store in Keychain", isOn: $isKeychain)
                } footer: {
                    Text("When enabled, the value is read at shell startup via `security find-generic-password`. This keeps secrets out of plain-text config files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isKeychain {
                    Section {
                        TextField("env/MY_SECRET", text: $keychainServiceName)
                            .textFieldStyle(.roundedBorder)
                            .fontDesign(.monospaced)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Keychain Service Name")
                    } footer: {
                        Text("The service name used to look up the value. Convention: env/VARIABLE_NAME")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField("Value", text: $value, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .fontDesign(.monospaced)
                            .lineLimit(1...4)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Value")
                    }
                }

                // Preview
                Section {
                    Text(previewLine)
                        .fontDesign(.monospaced)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Preview")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Variable" : "New Variable")
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
        .frame(width: 520, height: isKeychain ? 480 : 440)
    }

    // MARK: - Validation

    private var isValid: Bool {
        let trimmedKey = key.trimmed
        if trimmedKey.isEmpty { return false }
        if !isValidEnvVarName(trimmedKey) { return false }
        if isKeychain {
            return !keychainServiceName.trimmed.isEmpty
        } else {
            return !value.trimmed.isEmpty
        }
    }

    private func isValidEnvVarName(_ name: String) -> Bool {
        let pattern = /^[A-Za-z_][A-Za-z0-9_]*$/
        return name.wholeMatch(of: pattern) != nil
    }

    private func attemptSave() {
        let trimmedKey = key.trimmed

        if trimmedKey.isEmpty {
            validationError = "Variable name cannot be empty."
            return
        }

        if !isValidEnvVarName(trimmedKey) {
            validationError = "Invalid name. Use only letters, digits, and underscores."
            return
        }

        if isKeychain {
            if keychainServiceName.trimmed.isEmpty {
                validationError = "Keychain service name cannot be empty."
                return
            }
            let keychainValue = "$(security find-generic-password -s '\(keychainServiceName.trimmed)' -a \"$USER\" -w)"
            onSave(trimmedKey, keychainValue, true)
        } else {
            if value.trimmed.isEmpty {
                validationError = "Value cannot be empty."
                return
            }
            onSave(trimmedKey, value.trimmed, false)
        }
        dismiss()
    }

    // MARK: - Preview

    private var previewLine: String {
        let safeKey = key.trimmed.isEmpty ? "MY_VARIABLE" : key.trimmed
        if isKeychain {
            let service = keychainServiceName.trimmed.isEmpty ? "env/\(safeKey)" : keychainServiceName.trimmed
            return "export \(safeKey)=$(security find-generic-password -s '\(service)' -a \"$USER\" -w)"
        }
        let safeValue = value.trimmed.isEmpty ? "my_value" : value.trimmed
        if safeValue.contains("$(") || safeValue.contains("`") {
            return "export \(safeKey)=\(safeValue)"
        }
        return "export \(safeKey)=\"\(safeValue)\""
    }
}
