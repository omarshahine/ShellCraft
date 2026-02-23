import SwiftUI

struct SecretEditorSheet: View {
    /// If non-nil, we are editing an existing secret (only value can change).
    let secret: KeychainSecret?
    let onSave: (_ key: String, _ value: String, _ account: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var key: String
    @State private var value: String
    @State private var account: String
    @State private var validationError: String?

    private var isEditing: Bool { secret != nil }

    private var title: String {
        isEditing ? "Edit Secret" : "Add Secret"
    }

    private var isValid: Bool {
        !key.trimmed.isEmpty && !value.trimmed.isEmpty && !account.trimmed.isEmpty
    }

    init(secret: KeychainSecret?, onSave: @escaping (_ key: String, _ value: String, _ account: String) -> Void) {
        self.secret = secret
        self.onSave = onSave
        _key = State(initialValue: secret?.displayKey ?? "")
        _value = State(initialValue: "")
        _account = State(initialValue: secret?.account ?? NSUserName())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    keyField
                    accountField
                }

                Section("Value") {
                    SecureTextField(title: "Secret value", text: $value)
                }

                if let error = validationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if !isEditing {
                    Section {
                        Text("Stored as keychain generic password with service env/\(key.trimmed.isEmpty ? "KEY" : key.trimmed)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(width: 480, height: 340)
    }

    // MARK: - Key Field

    private var keyField: some View {
        HStack {
            Text("env/")
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)

            TextField("KEY_NAME", text: $key)
                .fontDesign(.monospaced)
                .textFieldStyle(.roundedBorder)
                .disabled(isEditing)
                .onChange(of: key) {
                    // Remove env/ prefix if user types it
                    if key.hasPrefix("env/") {
                        key = String(key.dropFirst(4))
                    }
                    validationError = nil
                }
        }
    }

    // MARK: - Account Field

    private var accountField: some View {
        TextField("Account", text: $account)
            .textFieldStyle(.roundedBorder)
            .disabled(isEditing)
            .help("The account name for this keychain entry (defaults to current user)")
    }

    // MARK: - Save

    private func save() {
        let trimmedKey = key.trimmed
        let trimmedValue = value.trimmed
        let trimmedAccount = account.trimmed

        guard !trimmedKey.isEmpty else {
            validationError = "Key name is required."
            return
        }

        guard !trimmedValue.isEmpty else {
            validationError = "Secret value is required."
            return
        }

        guard !trimmedAccount.isEmpty else {
            validationError = "Account name is required."
            return
        }

        // Validate key contains only reasonable characters
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-./"))
        if trimmedKey.unicodeScalars.contains(where: { !allowedChars.contains($0) }) {
            validationError = "Key name may only contain letters, numbers, underscores, hyphens, dots, and slashes."
            return
        }

        onSave(trimmedKey, trimmedValue, trimmedAccount)
        dismiss()
    }
}
