import Foundation

/// Parses and writes Ghostty's key=value config format at ~/.config/ghostty/config.
/// Preserves comments, blank lines, and ordering for round-trip safety.
struct GhosttyConfigService {

    static let configPath = "~/.config/ghostty/config"
    static let autoThemePath = "~/.config/ghostty/auto/theme.ghostty"

    // MARK: - Detection

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
    }

    static func configExists() -> Bool {
        FileIOService.fileExists(at: configPath)
    }

    static func autoThemeExists() -> Bool {
        FileIOService.fileExists(at: autoThemePath)
    }

    // MARK: - Parsing

    /// Parses the config file from disk. Returns the config and raw lines for round-trip writes.
    static func parse(path: String = configPath) throws -> (config: GhosttyConfig, rawLines: [String]) {
        let content = try FileIOService.readFile(at: path)
        return parse(content: content)
    }

    /// Pure parsing from string content.
    static func parse(content: String) -> (config: GhosttyConfig, rawLines: [String]) {
        let rawLines = content.components(separatedBy: "\n")
        var entries: [GhosttyConfigEntry] = []

        for line in rawLines {
            let trimmed = line.trimmed

            // Skip blank lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Parse key = value
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

            let key = String(trimmed[trimmed.startIndex..<equalsIndex]).trimmed
            var value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmed

            guard !key.isEmpty else { continue }

            // Strip inline comments (# not inside quotes)
            value = stripInlineComment(value)

            // Remove surrounding quotes from value if present
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            entries.append(GhosttyConfigEntry(key: key, value: value))
        }

        return (config: GhosttyConfig(entries: entries), rawLines: rawLines)
    }

    // MARK: - Writing

    /// Writes the config back to disk using round-trip safe strategy.
    /// Updates existing lines in rawLines, appends new keys at end.
    static func write(config: GhosttyConfig, rawLines: [String], path: String = configPath) throws {
        let content = applyChanges(config: config, rawLines: rawLines)

        // Ensure config directory exists
        let dirPath = (path as NSString).deletingLastPathComponent.expandingTildeInPath
        if !FileManager.default.fileExists(atPath: dirPath) {
            try FileManager.default.createDirectory(
                atPath: dirPath,
                withIntermediateDirectories: true
            )
        }

        try FileIOService.writeFile(at: path, content: content)
    }

    /// Applies config changes to raw lines, preserving comments and ordering.
    static func applyChanges(config: GhosttyConfig, rawLines: [String]) -> String {
        var updatedLines = rawLines
        var handledKeys: Set<String> = []

        // First pass: update existing lines
        for (lineIndex, line) in rawLines.enumerated() {
            let trimmed = line.trimmed
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

            let key = String(trimmed[trimmed.startIndex..<equalsIndex]).trimmed
            guard !key.isEmpty else { continue }

            if let entry = config.entries.last(where: { $0.key == key }) {
                // Key still exists in config, update the line
                let needsQuotes = entry.value.contains(" ") && !entry.value.hasPrefix("\"")
                let formattedValue = needsQuotes ? "\"\(entry.value)\"" : entry.value
                updatedLines[lineIndex] = "\(key) = \(formattedValue)"
                handledKeys.insert(key)
            } else {
                // Key was removed, comment it out
                updatedLines[lineIndex] = "# \(line)"
            }
        }

        // Second pass: append new keys not found in raw lines
        for entry in config.entries where !handledKeys.contains(entry.key) {
            let needsQuotes = entry.value.contains(" ") && !entry.value.hasPrefix("\"")
            let formattedValue = needsQuotes ? "\"\(entry.value)\"" : entry.value
            updatedLines.append("\(entry.key) = \(formattedValue)")
        }

        // Ensure trailing newline
        var result = updatedLines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    /// Clean serialization for export (no comment preservation).
    static func serialize(config: GhosttyConfig) -> String {
        var lines: [String] = [
            "# Ghostty Configuration",
            "# Exported by ShellCraft",
            ""
        ]

        for entry in config.entries {
            let needsQuotes = entry.value.contains(" ") && !entry.value.hasPrefix("\"")
            let formattedValue = needsQuotes ? "\"\(entry.value)\"" : entry.value
            lines.append("\(entry.key) = \(formattedValue)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Reload

    /// Checks if Ghostty is currently running.
    static func isRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "ghostty"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Sends SIGUSR1 to Ghostty to trigger a live config reload.
    /// Returns true if the signal was sent successfully.
    @discardableResult
    static func reloadConfig() -> Bool {
        guard isRunning() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-USR1", "ghostty"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Private

    private static func stripInlineComment(_ value: String) -> String {
        var inQuote = false
        var quoteChar: Character = "\""
        var result: [Character] = []

        for char in value {
            if !inQuote && char == "#" {
                break
            }
            if char == "\"" || char == "'" {
                if !inQuote {
                    inQuote = true
                    quoteChar = char
                } else if char == quoteChar {
                    inQuote = false
                }
            }
            result.append(char)
        }

        return String(result).trimmed
    }
}