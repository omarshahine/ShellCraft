import SwiftUI

struct SSHKeyGeneratorSheet: View {
    let onGenerate: (_ type: SSHKey.KeyType, _ name: String, _ passphrase: String, _ comment: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var keyType: SSHKey.KeyType = .ed25519
    @State private var keyName: String = "id_ed25519"
    @State private var passphrase: String = ""
    @State private var confirmPassphrase: String = ""
    @State private var comment: String = ""
    @State private var isGenerating: Bool = false
    @State private var generatedPublicKey: String?
    @State private var copied: Bool = false
    @State private var validationError: String?

    private var isValid: Bool {
        let name = keyName.trimmed
        guard !name.isEmpty else { return false }
        if !passphrase.isEmpty && passphrase != confirmPassphrase { return false }
        return true
    }

    private var defaultComment: String {
        "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
    }

    var body: some View {
        NavigationStack {
            if let publicKey = generatedPublicKey {
                generatedView(publicKey: publicKey)
                    .navigationTitle("Key Generated")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            } else {
                formView
                    .navigationTitle("Generate SSH Key")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button("Generate") { generate() }
                                    .disabled(!isValid)
                            }
                        }
                    }
            }
        }
        .frame(width: 520, height: generatedPublicKey != nil ? 380 : 460)
    }

    // MARK: - Form

    private var formView: some View {
        Form {
            Section("Key Type") {
                Picker("Algorithm", selection: $keyType) {
                    ForEach(SSHKey.KeyType.allCases) { type in
                        HStack {
                            Text(type.displayName)
                            if type == .ed25519 {
                                Text("(recommended)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            if type == .dsa {
                                Text("(deprecated)")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                        .tag(type)
                    }
                }
                .onChange(of: keyType) {
                    updateDefaultName()
                }
            }

            Section("Key File") {
                HStack {
                    Text("~/.ssh/")
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                    TextField("filename", text: $keyName)
                        .fontDesign(.monospaced)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: keyName) { validationError = nil }
                }

                if fileExists {
                    Label("A key with this name already exists and will be overwritten.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Passphrase (optional)") {
                SecureTextField(title: "Passphrase", text: $passphrase)

                if !passphrase.isEmpty {
                    SecureTextField(title: "Confirm passphrase", text: $confirmPassphrase)

                    if !confirmPassphrase.isEmpty && passphrase != confirmPassphrase {
                        Label("Passphrases do not match.", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            Section("Comment") {
                TextField("Comment", text: $comment, prompt: Text(defaultComment))
                    .help("A comment to identify this key (usually user@host)")
            }

            if keyType == .dsa {
                Section {
                    Label("DSA keys are deprecated and may not be supported.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let error = validationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Generated Key View

    private func generatedView(publicKey: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Your new \(keyType.displayName) key has been saved to ~/.ssh/\(keyName)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GroupBox("Public Key") {
                ScrollView {
                    Text(publicKey)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(height: 80)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(publicKey, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Label(
                    copied ? "Copied to Clipboard" : "Copy Public Key",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func generate() {
        let name = keyName.trimmed
        guard !name.isEmpty else {
            validationError = "Key filename is required."
            return
        }

        // Disallow path separators in filename
        if name.contains("/") || name.contains("\\") {
            validationError = "Key filename must not contain path separators."
            return
        }

        if !passphrase.isEmpty && passphrase != confirmPassphrase {
            validationError = "Passphrases do not match."
            return
        }

        isGenerating = true
        validationError = nil

        let effectiveComment = comment.trimmed.isEmpty ? defaultComment : comment.trimmed

        Task {
            // Call the onGenerate closure and read the generated public key
            onGenerate(keyType, name, passphrase, effectiveComment)

            // Wait briefly for key generation to complete, then read the public key
            try? await Task.sleep(for: .milliseconds(500))

            let pubPath = "~/.ssh/\(name).pub".expandingTildeInPath
            if let pubContent = try? FileIOService.readFile(at: pubPath) {
                generatedPublicKey = pubContent.trimmed
            } else {
                generatedPublicKey = "(Public key will be available at ~/.ssh/\(name).pub)"
            }

            isGenerating = false
        }
    }

    private func updateDefaultName() {
        switch keyType {
        case .ed25519: keyName = "id_ed25519"
        case .rsa: keyName = "id_rsa"
        case .ecdsa: keyName = "id_ecdsa"
        case .dsa: keyName = "id_dsa"
        }
    }

    private var fileExists: Bool {
        let path = "~/.ssh/\(keyName)".expandingTildeInPath
        return FileManager.default.fileExists(atPath: path)
    }
}
