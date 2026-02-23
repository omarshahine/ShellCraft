import Foundation

@MainActor @Observable
final class SecretsViewModel {

    // MARK: - Published State

    var secrets: [KeychainSecret] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var error: String?

    /// Tracks which secrets have their values visible in the UI.
    var revealedSecrets: Set<UUID> = []

    /// Caches the plain-text values of revealed secrets.
    var revealedValues: [UUID: String] = [:]

    /// Whether an add/edit sheet is showing.
    var showingEditor: Bool = false

    /// The secret currently being edited, or nil for a new secret.
    var editingSecret: KeychainSecret?

    // MARK: - Computed

    var filteredSecrets: [KeychainSecret] {
        guard !searchText.isEmpty else { return secrets }
        let query = searchText.lowercased()
        return secrets.filter {
            $0.displayKey.lowercased().contains(query) ||
            $0.account.lowercased().contains(query) ||
            $0.serviceName.lowercased().contains(query)
        }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        error = nil

        do {
            secrets = try await KeychainService.listSecrets()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Reveal / Hide

    func isRevealed(_ secret: KeychainSecret) -> Bool {
        revealedSecrets.contains(secret.id)
    }

    func toggleReveal(_ secret: KeychainSecret) async {
        if revealedSecrets.contains(secret.id) {
            revealedSecrets.remove(secret.id)
            revealedValues.removeValue(forKey: secret.id)
        } else {
            do {
                let value = try await KeychainService.readSecret(
                    serviceName: secret.serviceName,
                    account: secret.account
                )
                revealedValues[secret.id] = value
                revealedSecrets.insert(secret.id)
            } catch {
                self.error = "Failed to read secret: \(error.localizedDescription)"
            }
        }
    }

    /// Reads the secret value on demand (e.g., for clipboard copy).
    func revealValue(for secret: KeychainSecret) async -> String {
        // Return cached value if available
        if let cached = revealedValues[secret.id] {
            return cached
        }

        do {
            let value = try await KeychainService.readSecret(
                serviceName: secret.serviceName,
                account: secret.account
            )
            revealedValues[secret.id] = value
            return value
        } catch {
            self.error = "Failed to read secret: \(error.localizedDescription)"
            return ""
        }
    }

    // MARK: - Add

    func add(key: String, value: String, account: String? = nil) async {
        let serviceName = key.hasPrefix("env/") ? key : "env/\(key)"
        let effectiveAccount = account ?? NSUserName()

        do {
            try await KeychainService.addSecret(
                serviceName: serviceName,
                account: effectiveAccount,
                password: value
            )
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Update

    func update(_ secret: KeychainSecret, newValue: String) async {
        do {
            try await KeychainService.updateSecret(
                serviceName: secret.serviceName,
                account: secret.account,
                password: newValue
            )
            // Refresh the cached value if it was revealed
            if revealedSecrets.contains(secret.id) {
                revealedValues[secret.id] = newValue
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete

    func delete(_ secret: KeychainSecret) async {
        do {
            try await KeychainService.deleteSecret(
                serviceName: secret.serviceName,
                account: secret.account
            )
            revealedSecrets.remove(secret.id)
            revealedValues.removeValue(forKey: secret.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Editor Helpers

    func beginAdd() {
        editingSecret = nil
        showingEditor = true
    }

    func beginEdit(_ secret: KeychainSecret) {
        editingSecret = secret
        showingEditor = true
    }

    // MARK: - Encrypted Import / Export

    /// Reads the password for every secret from the keychain.
    /// May trigger keychain access dialogs. Silently skips secrets that fail to read.
    func gatherSecretsWithValues() async -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        for secret in secrets {
            do {
                let value = try await KeychainService.readSecret(
                    serviceName: secret.serviceName,
                    account: secret.account
                )
                result.append((key: secret.displayKey, value: value))
            } catch {
                // Skip secrets we can't read
            }
        }
        return result
    }

    /// Encrypts all readable secrets into AES-256-CBC format.
    func exportEncryptedData(password: String) async throws -> Data {
        let secrets = await gatherSecretsWithValues()
        let plaintext = secrets.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        return try await EncryptionService.encrypt(plaintext: plaintext, password: password)
    }

    /// Imports decrypted key/value pairs into the keychain (only new entries).
    func applyEncryptedImport(_ entries: [(key: String, value: String)]) async {
        for entry in entries {
            let serviceName = entry.key.hasPrefix("env/") ? entry.key : "env/\(entry.key)"
            do {
                try await KeychainService.addSecret(
                    serviceName: serviceName,
                    account: NSUserName(),
                    password: entry.value
                )
            } catch {
                self.error = "Failed to import \(serviceName): \(error.localizedDescription)"
            }
        }
        await load()
    }

    // MARK: - Schema Import / Export

    /// Exports secret key names only (no values for security).
    func exportData() -> String {
        let entries = secrets.map { secret in
            ["serviceName": secret.serviceName, "account": secret.account]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    func previewImport(_ content: String) -> ImportPreview {
        guard let data = content.data(using: .utf8),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return ImportPreview(
                fileName: "", sectionName: "Secrets", isReplace: false,
                newItems: [], updatedItems: [], unchangedCount: 0,
                warnings: ["Could not parse JSON file."]
            )
        }

        let existingServices = Set(secrets.map(\.serviceName))
        var newItems: [String] = []
        var unchanged = 0

        for entry in entries {
            guard let serviceName = entry["serviceName"] else { continue }
            if existingServices.contains(serviceName) {
                unchanged += 1
            } else {
                newItems.append(serviceName)
            }
        }

        var warnings: [String] = []
        let hasValues = entries.contains { $0["value"] != nil }
        if !hasValues {
            warnings.append("Import file contains key names only — no values will be written to Keychain.")
        }

        return ImportPreview(
            fileName: "",
            sectionName: "Secrets",
            isReplace: false,
            newItems: newItems,
            updatedItems: [],
            unchangedCount: unchanged,
            warnings: warnings
        )
    }

    func applyImport(_ content: String) async {
        guard let data = content.data(using: .utf8),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            error = "Failed to parse imported secrets JSON."
            return
        }

        let existingServices = Set(secrets.map(\.serviceName))

        for entry in entries {
            guard let serviceName = entry["serviceName"],
                  let account = entry["account"],
                  let value = entry["value"],
                  !value.isEmpty,
                  !existingServices.contains(serviceName) else { continue }

            do {
                try await KeychainService.addSecret(
                    serviceName: serviceName,
                    account: account,
                    password: value
                )
            } catch {
                self.error = "Failed to import \(serviceName): \(error.localizedDescription)"
            }
        }

        await load()
    }
}
