import Foundation

enum EncryptionError: LocalizedError {
    case encryptionFailed(detail: String)
    case decryptionFailed
    case opensslNotFound

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let detail):
            "Encryption failed: \(detail)"
        case .decryptionFailed:
            "Decryption failed — wrong password or corrupted file."
        case .opensslNotFound:
            "openssl was not found on this system."
        }
    }
}

/// Wraps `openssl enc` for AES-256-CBC encryption/decryption via temp files.
///
/// Format is compatible with the user's existing `keychain-export.sh` / `keychain-import.sh`:
/// `openssl enc -aes-256-cbc -salt -pbkdf2`
struct EncryptionService {

    /// Encrypts plaintext to an AES-256-CBC ciphertext blob.
    static func encrypt(plaintext: String, password: String) async throws -> Data {
        guard await ProcessService.commandExists("openssl") else {
            throw EncryptionError.opensslNotFound
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let inputURL = tmpDir.appendingPathComponent(UUID().uuidString + ".plain")
        let outputURL = tmpDir.appendingPathComponent(UUID().uuidString + ".enc")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Write plaintext with restricted permissions
        FileManager.default.createFile(
            atPath: inputURL.path,
            contents: plaintext.data(using: .utf8),
            attributes: [.posixPermissions: 0o600]
        )

        let command = [
            "openssl enc -aes-256-cbc -salt -pbkdf2",
            "-in", inputURL.path.singleQuoted,
            "-out", outputURL.path.singleQuoted,
            "-pass", "pass:\(password.shellEscaped)",
        ].joined(separator: " ")

        let result = try await ProcessService.run(command)

        guard result.succeeded else {
            throw EncryptionError.encryptionFailed(detail: result.error)
        }

        guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
            throw EncryptionError.encryptionFailed(detail: "Output file was empty.")
        }

        return data
    }

    /// Decrypts an AES-256-CBC ciphertext blob back to plaintext.
    static func decrypt(data: Data, password: String) async throws -> String {
        guard await ProcessService.commandExists("openssl") else {
            throw EncryptionError.opensslNotFound
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let inputURL = tmpDir.appendingPathComponent(UUID().uuidString + ".enc")
        let outputURL = tmpDir.appendingPathComponent(UUID().uuidString + ".plain")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Write encrypted data with restricted permissions
        FileManager.default.createFile(
            atPath: inputURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )

        let command = [
            "openssl enc -aes-256-cbc -d -salt -pbkdf2",
            "-in", inputURL.path.singleQuoted,
            "-out", outputURL.path.singleQuoted,
            "-pass", "pass:\(password.shellEscaped)",
        ].joined(separator: " ")

        let result = try await ProcessService.run(command)

        guard result.succeeded else {
            throw EncryptionError.decryptionFailed
        }

        guard let plaintext = try? String(contentsOf: outputURL, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        return plaintext
    }
}
