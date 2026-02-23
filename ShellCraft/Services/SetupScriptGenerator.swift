import Foundation

/// Configuration for what to include in the generated setup script.
struct SetupScriptConfig {
    var secrets: [(key: String, value: String)]
    var includeKeychainHelper: Bool = true
    var includeExportStatements: Bool = true
    var pathEntries: [String] = []
    var envVars: [(key: String, value: String)] = []
    var password: String
}

/// Generates a self-contained bash script that imports encrypted keychain secrets
/// and optionally configures PATH, env vars, and the `keychain_secret()` helper.
///
/// Compatible with the existing `keychain-import.sh` conventions (same markers,
/// same `env/` prefix pattern, same `security add-generic-password` commands).
struct SetupScriptGenerator {

    static func generate(config: SetupScriptConfig) async throws -> String {
        // Build the KEY=VALUE plaintext for encryption
        let secretLines = config.secrets.map { "\($0.key)=\($0.value)" }
        let plaintext = secretLines.joined(separator: "\n")

        // Encrypt and base64-encode
        let encrypted = try await EncryptionService.encrypt(plaintext: plaintext, password: config.password)
        let base64 = encrypted.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])

        var script = ""

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date())

        script += """
        #!/bin/bash
        #
        # ShellCraft Setup Script
        # Generated: \(date)
        #
        # This script imports encrypted keychain secrets and configures your shell.
        # It requires openssl and the macOS security command.
        #
        set -euo pipefail

        echo "ShellCraft Setup Script"
        echo "======================"
        echo ""

        """

        // Encrypted blob
        script += """
        # --- Encrypted Secrets (AES-256-CBC, PBKDF2) ---
        ENCRYPTED_SECRETS=$(cat <<'BLOB'
        \(base64)
        BLOB
        )

        """

        // Decrypt and import logic
        script += """
        # Prompt for password
        read -s -p "Enter decryption password: " DECRYPT_PASS
        echo ""

        # Decrypt secrets
        TMPFILE=$(mktemp)
        DECRYPTED=$(mktemp)
        chmod 600 "$TMPFILE" "$DECRYPTED"
        trap 'rm -f "$TMPFILE" "$DECRYPTED"' EXIT

        echo "$ENCRYPTED_SECRETS" | base64 -d > "$TMPFILE"

        if ! openssl enc -aes-256-cbc -d -salt -pbkdf2 -in "$TMPFILE" -out "$DECRYPTED" -pass pass:"$DECRYPT_PASS" 2>/dev/null; then
            echo "ERROR: Decryption failed. Wrong password?"
            exit 1
        fi

        echo "Decryption successful. Importing secrets..."
        echo ""

        # Import each secret to keychain
        IMPORTED=0
        SKIPPED=0
        while IFS='=' read -r KEY VALUE; do
            [ -z "$KEY" ] && continue
            SERVICE="env/$KEY"
            ACCOUNT="$USER"

            # Check if it already exists
            if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
                echo "  SKIP: $SERVICE (already exists)"
                SKIPPED=$((SKIPPED + 1))
            else
                if security add-generic-password -s "$SERVICE" -a "$ACCOUNT" -w "$VALUE"; then
                    echo "  ADD:  $SERVICE"
                    IMPORTED=$((IMPORTED + 1))
                else
                    echo "  FAIL: $SERVICE"
                fi
            fi
        done < "$DECRYPTED"

        echo ""
        echo "Imported: $IMPORTED, Skipped: $SKIPPED"

        """

        // Optional: keychain_secret() helper
        if config.includeKeychainHelper {
            script += """

            # --- keychain_secret() Helper ---
            ZSHRC="$HOME/.zshrc"
            if ! grep -q 'keychain_secret()' "$ZSHRC" 2>/dev/null; then
                echo "" >> "$ZSHRC"
                cat >> "$ZSHRC" <<'HELPER'

            # ShellCraft: keychain_secret helper
            keychain_secret() {
                security find-generic-password -s "$1" -a "$USER" -w 2>/dev/null
            }
            HELPER
                echo "Added keychain_secret() helper to ~/.zshrc"
            else
                echo "keychain_secret() helper already present in ~/.zshrc"
            fi

            """
        }

        // Optional: export statements
        if config.includeExportStatements && !config.secrets.isEmpty {
            script += """

            # --- Export Statements ---
            MARKER="# ShellCraft: Keychain-backed exports"
            if ! grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
                echo "" >> "$ZSHRC"
                echo "$MARKER" >> "$ZSHRC"

            """

            for secret in config.secrets {
                let varName = secret.key
                script += "    echo 'export \(varName)=$(keychain_secret \"env/\(varName)\")' >> \"$ZSHRC\"\n"
            }

            script += """
                echo "Added export statements to ~/.zshrc"
            else
                echo "Export statements marker already present in ~/.zshrc"
            fi

            """
        }

        // Optional: PATH entries
        if !config.pathEntries.isEmpty {
            let pathValue = config.pathEntries.joined(separator: ":")
            script += """

            # --- PATH Configuration ---
            PATH_MARKER="# ShellCraft: PATH"
            if ! grep -q "$PATH_MARKER" "$ZSHRC" 2>/dev/null; then
                echo "" >> "$ZSHRC"
                echo "$PATH_MARKER" >> "$ZSHRC"
                echo 'export PATH="\(pathValue):$PATH"' >> "$ZSHRC"
                echo "Added PATH entries to ~/.zshrc"
            else
                echo "PATH marker already present in ~/.zshrc"
            fi

            """
        }

        // Optional: non-keychain env vars
        let nonKeychainVars = config.envVars.filter { !$0.value.contains("keychain_secret") }
        if !nonKeychainVars.isEmpty {
            script += """

            # --- Environment Variables ---
            ENV_MARKER="# ShellCraft: Environment Variables"
            if ! grep -q "$ENV_MARKER" "$ZSHRC" 2>/dev/null; then
                echo "" >> "$ZSHRC"
                echo "$ENV_MARKER" >> "$ZSHRC"

            """

            for envVar in nonKeychainVars {
                let escaped = envVar.value.replacingOccurrences(of: "\"", with: "\\\"")
                script += "    echo 'export \(envVar.key)=\"\(escaped)\"' >> \"$ZSHRC\"\n"
            }

            script += """
                echo "Added environment variables to ~/.zshrc"
            else
                echo "Environment variable marker already present in ~/.zshrc"
            fi

            """
        }

        // Footer
        script += """

        echo ""
        echo "Setup complete! Run 'source ~/.zshrc' to apply changes."
        """

        return script
    }
}
