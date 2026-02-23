import Foundation

@MainActor @Observable
final class SSHConfigViewModel {

    // MARK: - Tab Selection

    enum Tab: String, CaseIterable, Identifiable {
        case hosts = "Hosts"
        case keys = "Keys"

        var id: String { rawValue }
    }

    // MARK: - Published State

    var hosts: [SSHHost] = []
    var keys: [SSHKey] = []
    var searchText: String = ""
    var selectedTab: Tab = .hosts
    var hasUnsavedChanges: Bool = false
    var isLoading: Bool = false
    var error: String?

    /// Original hosts loaded from disk, used to detect changes.
    private var originalHosts: [SSHHost] = []

    /// Editor sheet state
    var showingHostEditor: Bool = false
    var editingHost: SSHHost?

    /// Key generator sheet state
    var showingKeyGenerator: Bool = false

    // MARK: - Computed

    var filteredHosts: [SSHHost] {
        guard !searchText.isEmpty else { return hosts }
        let query = searchText.lowercased()
        return hosts.filter {
            $0.host.lowercased().contains(query) ||
            $0.hostname.lowercased().contains(query) ||
            $0.user.lowercased().contains(query)
        }
    }

    var filteredKeys: [SSHKey] {
        guard !searchText.isEmpty else { return keys }
        let query = searchText.lowercased()
        return keys.filter {
            $0.path.lowercased().contains(query) ||
            $0.type.displayName.lowercased().contains(query) ||
            $0.fingerprint.lowercased().contains(query)
        }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        error = nil

        do {
            hosts = try SSHConfigParser.parse()
            originalHosts = hosts
            hasUnsavedChanges = false
        } catch {
            self.error = "Failed to parse SSH config: \(error.localizedDescription)"
        }

        await scanKeys()
        isLoading = false
    }

    // MARK: - Save

    func save() {
        do {
            try SSHConfigParser.save(hosts: hosts)
            originalHosts = hosts
            hasUnsavedChanges = false
        } catch {
            self.error = "Failed to save SSH config: \(error.localizedDescription)"
        }
    }

    func discard() {
        hosts = originalHosts
        hasUnsavedChanges = false
    }

    // MARK: - Host CRUD

    func addHost(_ host: SSHHost) {
        hosts.append(host)
        hasUnsavedChanges = true
    }

    func updateHost(_ host: SSHHost) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
            hasUnsavedChanges = true
        }
    }

    func deleteHost(_ host: SSHHost) {
        hosts.removeAll { $0.id == host.id }
        hasUnsavedChanges = true
    }

    func deleteHost(at offsets: IndexSet) {
        hosts.remove(atOffsets: offsets)
        hasUnsavedChanges = true
    }

    // MARK: - Editor Helpers

    func beginAddHost() {
        editingHost = nil
        showingHostEditor = true
    }

    func beginEditHost(_ host: SSHHost) {
        editingHost = host
        showingHostEditor = true
    }

    // MARK: - SSH Keys

    /// Scans `~/.ssh/` for private key files and reads their metadata.
    func scanKeys() async {
        let sshDir = "~/.ssh".expandingTildeInPath
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sshDir) else {
            keys = []
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: sshDir)
            var discoveredKeys: [SSHKey] = []

            for filename in contents.sorted() {
                let fullPath = "\(sshDir)/\(filename)"

                // Skip directories, public keys, config, known_hosts, and other non-key files
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
                if isDir.boolValue { continue }
                if filename.hasSuffix(".pub") { continue }
                if filename == "config" || filename == "known_hosts" || filename == "authorized_keys" { continue }
                if filename.hasPrefix(".") { continue }
                if filename == "known_hosts.old" || filename == "environment" { continue }

                // Check if this looks like a private key by examining the first line
                guard let firstLine = try? FileIOService.readLines(at: fullPath).first,
                      firstLine.contains("PRIVATE KEY") || firstLine.contains("OPENSSH PRIVATE KEY")
                else { continue }

                let keyType = detectKeyType(from: filename, firstLine: firstLine)
                let fingerprint = await getFingerprint(for: fullPath)
                let publicKey = readPublicKey(for: fullPath)

                discoveredKeys.append(SSHKey(
                    path: fullPath,
                    type: keyType,
                    fingerprint: fingerprint,
                    publicKey: publicKey
                ))
            }

            keys = discoveredKeys
        } catch {
            self.error = "Failed to scan SSH keys: \(error.localizedDescription)"
        }
    }

    /// Generates a new SSH key pair using `ssh-keygen`.
    func generateKey(type: SSHKey.KeyType, name: String, passphrase: String, comment: String) async -> SSHKey? {
        let sshDir = "~/.ssh".expandingTildeInPath
        let keyPath = "\(sshDir)/\(name)"

        // Build the ssh-keygen command
        var args = "ssh-keygen -t \(type.rawValue)"

        // Ed25519 does not accept a bits parameter
        if type == .rsa {
            args += " -b 4096"
        }

        args += " -f \(keyPath.singleQuoted)"
        args += " -N \(passphrase.singleQuoted)"

        if !comment.isEmpty {
            args += " -C \(comment.singleQuoted)"
        }

        do {
            let result = try await ProcessService.run(args)
            guard result.succeeded else {
                self.error = "Key generation failed: \(result.error)"
                return nil
            }

            let fingerprint = await getFingerprint(for: keyPath)
            let publicKey = readPublicKey(for: keyPath)

            let newKey = SSHKey(
                path: keyPath,
                type: type,
                fingerprint: fingerprint,
                publicKey: publicKey,
                hasPassphrase: !passphrase.isEmpty
            )

            // Refresh the keys list
            await scanKeys()

            return newKey
        } catch {
            self.error = "Key generation failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Import / Export

    func exportData() -> String {
        SSHConfigParser.write(hosts: hosts)
    }

    func previewImport(_ content: String) -> ImportPreview {
        let imported = SSHConfigParser.parse(content: content)
        let existingHosts = Set(hosts.map(\.host))
        var newItems: [String] = []
        var updatedItems: [String] = []
        var unchanged = 0

        for host in imported {
            if existingHosts.contains(host.host) {
                // Check if anything changed
                if let existing = hosts.first(where: { $0.host == host.host }),
                   existing.hostname != host.hostname || existing.user != host.user ||
                   existing.identityFile != host.identityFile || existing.port != host.port {
                    updatedItems.append(host.host)
                } else {
                    unchanged += 1
                }
            } else {
                newItems.append(host.host)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "SSH Hosts",
            isReplace: false,
            newItems: newItems,
            updatedItems: updatedItems,
            unchangedCount: unchanged,
            warnings: []
        )
    }

    func applyImport(_ content: String) {
        let imported = SSHConfigParser.parse(content: content)

        for importedHost in imported {
            if let index = hosts.firstIndex(where: { $0.host == importedHost.host }) {
                hosts[index] = importedHost
            } else {
                hosts.append(importedHost)
            }
        }

        hasUnsavedChanges = true
    }

    // MARK: - Key Deletion

    /// Moves a key pair (private + public) to the Trash and refreshes the key list.
    func deleteKey(_ key: SSHKey) async {
        let privateKeyPath = key.path
        let publicKeyPath = privateKeyPath + ".pub"

        // Build trash command for private key, and optionally the public key
        var paths = privateKeyPath.singleQuoted
        if FileManager.default.fileExists(atPath: publicKeyPath) {
            paths += " " + publicKeyPath.singleQuoted
        }

        do {
            let result = try await ProcessService.run("trash \(paths)")
            if !result.succeeded {
                self.error = "Failed to delete key: \(result.error)"
            }
        } catch {
            self.error = "Failed to delete key: \(error.localizedDescription)"
        }

        await scanKeys()
    }

    // MARK: - Key Helpers

    private func detectKeyType(from filename: String, firstLine: String) -> SSHKey.KeyType {
        let name = filename.lowercased()
        if name.contains("ed25519") { return .ed25519 }
        if name.contains("ecdsa") { return .ecdsa }
        if name.contains("dsa") && !name.contains("ecdsa") { return .dsa }
        if name.contains("rsa") { return .rsa }

        // Fall back to checking the header
        let header = firstLine.lowercased()
        if header.contains("openssh") { return .ed25519 }  // Modern OpenSSH format is typically ed25519
        if header.contains("rsa") { return .rsa }
        if header.contains("ec") { return .ecdsa }
        if header.contains("dsa") { return .dsa }

        return .rsa  // Default fallback
    }

    private func getFingerprint(for keyPath: String) async -> String {
        do {
            let result = try await ProcessService.run("ssh-keygen -lf \(keyPath.singleQuoted)")
            if result.succeeded {
                return result.output.trimmed
            }
        } catch {
            // Silently fail for fingerprint — non-critical
        }
        return ""
    }

    private func readPublicKey(for privateKeyPath: String) -> String {
        let pubPath = privateKeyPath + ".pub"
        guard let content = try? FileIOService.readFile(at: pubPath) else { return "" }
        return content.trimmed
    }
}
