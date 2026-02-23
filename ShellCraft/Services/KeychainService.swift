import Foundation

struct KeychainService {

    // MARK: - List Secrets

    /// Lists all keychain generic passwords whose service name starts with `env/`.
    /// Uses `security dump-keychain` (no `-d` flag to avoid password prompts).
    static func listSecrets() async throws -> [KeychainSecret] {
        let result = try await ProcessService.run("security dump-keychain")

        // `dump-keychain` writes to stdout. Combine both just in case.
        let combined = result.output + "\n" + result.error

        return parseKeychainDump(combined)
    }

    /// Parses the text output of `security dump-keychain` looking for generic password items
    /// whose `"svce"` (service) attribute starts with `env/`.
    private static func parseKeychainDump(_ text: String) -> [KeychainSecret] {
        var secrets: [KeychainSecret] = []
        let lines = text.components(separatedBy: "\n")

        var inGenericPassword = false
        var currentService: String?
        var currentAccount: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect the start of a generic password item
            if trimmed.hasPrefix("keychain:") || trimmed.hasPrefix("class:") {
                // Save any pending item before starting a new block
                if inGenericPassword, let service = currentService, service.hasPrefix("env/") {
                    let account = currentAccount ?? ""
                    secrets.append(
                        KeychainSecret(serviceName: service, account: account)
                    )
                }
                inGenericPassword = trimmed.contains("\"genp\"")
                currentService = nil
                currentAccount = nil
                continue
            }

            guard inGenericPassword else { continue }

            // Parse "svce"<blob>="env/MY_SECRET"
            if let value = extractAttributeValue(from: trimmed, attribute: "svce") {
                currentService = value
            }

            // Parse "acct"<blob>="username"
            if let value = extractAttributeValue(from: trimmed, attribute: "acct") {
                currentAccount = value
            }
        }

        // Flush the last item
        if inGenericPassword, let service = currentService, service.hasPrefix("env/") {
            let account = currentAccount ?? ""
            secrets.append(
                KeychainSecret(serviceName: service, account: account)
            )
        }

        // Deduplicate by (serviceName, account)
        var seen: Set<String> = []
        return secrets.filter { secret in
            let key = "\(secret.serviceName)|\(secret.account)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    /// Extracts a value from a keychain dump attribute line.
    /// Lines look like: `"svce"<blob>="env/MY_KEY"` or `"svce"<blob>=0x6D79...  "readable"`
    private static func extractAttributeValue(from line: String, attribute: String) -> String? {
        // Match the attribute name in quotes
        guard line.contains("\"\(attribute)\"") else { return nil }

        // Try the simple quoted form: "attr"<blob>="value"
        if let equalsRange = line.range(of: "=\"") {
            let afterEquals = line[equalsRange.upperBound...]
            if let closingQuote = afterEquals.range(of: "\"") {
                let value = String(afterEquals[..<closingQuote.lowerBound])
                return value.isEmpty ? nil : value
            }
        }

        // Try hex form: "attr"<blob>=0xHEXDATA  "readable string"
        // The readable form is at the end in quotes
        if line.contains("=0x") {
            // Look for the trailing quoted string
            if let lastQuote = line.lastIndex(of: "\"") {
                let beforeLast = line[..<lastQuote]
                if let secondLastQuote = beforeLast.lastIndex(of: "\"") {
                    let value = String(beforeLast[beforeLast.index(after: secondLastQuote)...])
                    return value.isEmpty ? nil : value
                }
            }
        }

        return nil
    }

    // MARK: - Read Secret

    /// Reads the password value for a specific keychain item.
    static func readSecret(serviceName: String, account: String) async throws -> String {
        let command = "security find-generic-password -s \(serviceName.singleQuoted) -a \(account.singleQuoted) -w"
        let result = try await ProcessService.run(command)

        guard result.succeeded else {
            throw KeychainError.secretNotFound(serviceName: serviceName, account: account)
        }

        return result.output.trimmed
    }

    // MARK: - Add Secret

    /// Adds a new generic password to the keychain.
    static func addSecret(serviceName: String, account: String, password: String) async throws {
        let command = "security add-generic-password -s \(serviceName.singleQuoted) -a \(account.singleQuoted) -w \(password.singleQuoted)"
        let result = try await ProcessService.run(command)

        guard result.succeeded else {
            // Exit code 45 means the item already exists
            if result.exitCode == 45 {
                throw KeychainError.duplicateItem(serviceName: serviceName, account: account)
            }
            throw KeychainError.commandFailed(detail: result.error)
        }
    }

    // MARK: - Update Secret

    /// Updates an existing keychain secret by deleting and re-adding it.
    /// The macOS keychain CLI does not have a direct update command.
    static func updateSecret(serviceName: String, account: String, password: String) async throws {
        try await deleteSecret(serviceName: serviceName, account: account)
        try await addSecret(serviceName: serviceName, account: account, password: password)
    }

    // MARK: - Delete Secret

    /// Deletes a generic password from the keychain.
    static func deleteSecret(serviceName: String, account: String) async throws {
        let command = "security delete-generic-password -s \(serviceName.singleQuoted) -a \(account.singleQuoted)"
        let result = try await ProcessService.run(command)

        guard result.succeeded else {
            throw KeychainError.secretNotFound(serviceName: serviceName, account: account)
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case secretNotFound(serviceName: String, account: String)
    case duplicateItem(serviceName: String, account: String)
    case commandFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .secretNotFound(let service, let account):
            "Secret not found: \(service) (\(account))"
        case .duplicateItem(let service, let account):
            "Secret already exists: \(service) (\(account))"
        case .commandFailed(let detail):
            "Keychain operation failed: \(detail)"
        }
    }
}
