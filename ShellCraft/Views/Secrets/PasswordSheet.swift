import SwiftUI

/// Reusable sheet for entering or confirming an encryption password.
struct PasswordSheet: View {
    enum Mode {
        case encrypt
        case decrypt
    }

    let mode: Mode
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var validationError: String?

    private var title: String {
        switch mode {
        case .encrypt: "Set Encryption Password"
        case .decrypt: "Enter Decryption Password"
        }
    }

    private var isValid: Bool {
        switch mode {
        case .encrypt:
            password.count >= 8 && password == confirmPassword
        case .decrypt:
            !password.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text(title)
                    .font(.headline)

                Spacer()

                Button("Continue") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                if mode == .encrypt {
                    Text("Choose a password to protect your exported secrets. You will need this password to import them on another machine.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: password) { validationError = nil }
                }

                if mode == .encrypt {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        SecureField("Re-enter password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: confirmPassword) { validationError = nil }
                    }

                    if password.count > 0 && password.count < 8 {
                        Label("Password must be at least 8 characters", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if !confirmPassword.isEmpty && password != confirmPassword {
                        Label("Passwords do not match", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)

            Spacer()
        }
        .frame(width: 400, height: mode == .encrypt ? 320 : 220)
    }

    private func submit() {
        if mode == .encrypt {
            guard password.count >= 8 else {
                validationError = "Password must be at least 8 characters."
                return
            }
            guard password == confirmPassword else {
                validationError = "Passwords do not match."
                return
            }
        } else {
            guard !password.isEmpty else {
                validationError = "Password is required."
                return
            }
        }

        onSubmit(password)
        dismiss()
    }
}
