import SwiftUI

/// Two-phase sheet for importing encrypted secrets:
/// 1. Password entry → decrypt
/// 2. Preview found secrets → import to keychain
struct EncryptedImportSheet: View {
    let encryptedData: Data
    let fileName: String
    let viewModel: SecretsViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var password: String = ""
    @State private var decryptionError: String?
    @State private var isDecrypting: Bool = false
    @State private var decryptedEntries: [(key: String, value: String)] = []
    @State private var isDecrypted: Bool = false
    @State private var isImporting: Bool = false

    private var existingServiceNames: Set<String> {
        Set(viewModel.secrets.map(\.serviceName))
    }

    private var newEntries: [(key: String, value: String)] {
        decryptedEntries.filter { !existingServiceNames.contains("env/\($0.key)") }
    }

    private var existingEntries: [(key: String, value: String)] {
        decryptedEntries.filter { existingServiceNames.contains("env/\($0.key)") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Import Encrypted Secrets")
                    .font(.headline)

                Spacer()

                if isDecrypted {
                    Button("Import") { performImport() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(newEntries.isEmpty || isImporting)
                }
            }
            .padding()

            Divider()

            if !isDecrypted {
                passwordPhase
            } else {
                previewPhase
            }
        }
        .frame(width: 500, height: isDecrypted ? 420 : 240)
    }

    // MARK: - Password Phase

    private var passwordPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.callout)
                    .fontDesign(.monospaced)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField("Enter decryption password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { decrypt() }
                    .onChange(of: password) { decryptionError = nil }
            }

            if let error = decryptionError {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Decrypt") { decrypt() }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isDecrypting)

                if isDecrypting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Preview Phase

    private var previewPhase: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary badges
            HStack(spacing: 12) {
                if !newEntries.isEmpty {
                    badge(count: newEntries.count, label: "new", color: .green, icon: "plus.circle")
                }
                if !existingEntries.isEmpty {
                    badge(count: existingEntries.count, label: "existing (skip)", color: .gray, icon: "checkmark.circle")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // List of entries
            List {
                if !newEntries.isEmpty {
                    Section("New Secrets") {
                        ForEach(newEntries, id: \.key) { entry in
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text("env/\(entry.key)")
                                    .fontDesign(.monospaced)
                                    .font(.callout)
                            }
                        }
                    }
                }

                if !existingEntries.isEmpty {
                    Section("Already Exists (Will Skip)") {
                        ForEach(existingEntries, id: \.key) { entry in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.gray)
                                    .font(.caption)
                                Text("env/\(entry.key)")
                                    .fontDesign(.monospaced)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if isImporting {
                HStack {
                    Spacer()
                    ProgressView("Importing...")
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Actions

    private func decrypt() {
        isDecrypting = true
        decryptionError = nil

        Task {
            do {
                let plaintext = try await EncryptionService.decrypt(data: encryptedData, password: password)
                let entries = parseKeyValueLines(plaintext)
                if entries.isEmpty {
                    decryptionError = "File decrypted but contained no valid KEY=VALUE entries."
                } else {
                    decryptedEntries = entries
                    isDecrypted = true
                }
            } catch is EncryptionError {
                decryptionError = "Wrong password or corrupted file. Please try again."
            } catch {
                decryptionError = error.localizedDescription
            }
            isDecrypting = false
        }
    }

    private func performImport() {
        isImporting = true

        Task {
            await viewModel.applyEncryptedImport(newEntries)
            isImporting = false
            dismiss()
        }
    }

    /// Parses `KEY=VALUE` lines, ignoring blank lines and comments.
    private func parseKeyValueLines(_ text: String) -> [(key: String, value: String)] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { return nil }
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return (key: key, value: value)
        }
    }

    private func badge(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(count) \(label)")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
