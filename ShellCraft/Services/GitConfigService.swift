import Foundation

/// INI-style parser and writer for ~/.gitconfig files.
/// Handles [section], [section "subsection"], key = value, comments, and blank lines.
struct GitConfigService {

    // MARK: - Parsing

    static func parse(path: String = "~/.gitconfig") throws -> GitConfig {
        let content = try FileIOService.readFile(at: path)
        return parse(content: content)
    }

    static func parse(content: String) -> GitConfig {
        let lines = content.components(separatedBy: "\n")
        var sections: [GitConfigSection] = []
        var currentSection: GitConfigSection?

        for line in lines {
            let trimmed = line.trimmed

            // Skip blank lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            // Check for section header: [section] or [section "subsection"]
            if let header = parseSectionHeader(trimmed) {
                // Save previous section if any
                if let section = currentSection {
                    // Merge with existing section of same name/subsection for multi-value support
                    if let existingIndex = sections.firstIndex(where: {
                        $0.name == section.name && $0.subsection == section.subsection
                    }) {
                        sections[existingIndex].entries.append(contentsOf: section.entries)
                    } else {
                        sections.append(section)
                    }
                }
                currentSection = GitConfigSection(
                    name: header.name,
                    subsection: header.subsection
                )
                continue
            }

            // Parse key = value within current section
            if var section = currentSection, let entry = parseEntry(trimmed) {
                section.entries.append(entry)
                currentSection = section
            }
        }

        // Don't forget the last section
        if let section = currentSection {
            if let existingIndex = sections.firstIndex(where: {
                $0.name == section.name && $0.subsection == section.subsection
            }) {
                sections[existingIndex].entries.append(contentsOf: section.entries)
            } else {
                sections.append(section)
            }
        }

        return GitConfig(sections: sections)
    }

    // MARK: - Writing

    static func write(config: GitConfig, path: String = "~/.gitconfig") throws {
        let content = serialize(config: config)
        try FileIOService.writeFile(at: path, content: content)
    }

    static func serialize(config: GitConfig) -> String {
        var lines: [String] = []

        // Group sections by name+subsection to handle multi-value keys properly
        var seen: Set<String> = []

        for section in config.sections {
            let key = sectionKey(name: section.name, subsection: section.subsection)
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            // Collect all entries for this section (across duplicates)
            let allEntries = config.sections
                .filter { $0.name == section.name && $0.subsection == section.subsection }
                .flatMap(\.entries)

            // Add blank line before section (except the first)
            if !lines.isEmpty {
                lines.append("")
            }

            // Write section header
            if let subsection = section.subsection {
                lines.append("[\(section.name) \"\(subsection)\"]")
            } else {
                lines.append("[\(section.name)]")
            }

            // Write entries
            for entry in allEntries {
                lines.append("\t\(entry.key) = \(entry.value)")
            }
        }

        // Ensure trailing newline
        if !lines.isEmpty {
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private struct SectionHeader {
        let name: String
        let subsection: String?
    }

    /// Parses a section header like [core] or [remote "origin"]
    private static func parseSectionHeader(_ line: String) -> SectionHeader? {
        guard line.hasPrefix("[") && line.hasSuffix("]") else { return nil }

        let inner = String(line.dropFirst().dropLast()).trimmed

        // Check for subsection: section "subsection"
        if let quoteStart = inner.firstIndex(of: "\""),
           let quoteEnd = inner.lastIndex(of: "\""),
           quoteStart != quoteEnd {
            let name = String(inner[inner.startIndex..<quoteStart]).trimmed
            let subsection = String(inner[inner.index(after: quoteStart)..<quoteEnd])
            return SectionHeader(name: name, subsection: subsection.isEmpty ? nil : subsection)
        }

        // Simple section
        return SectionHeader(name: inner, subsection: nil)
    }

    /// Parses a key = value entry, handling inline comments
    private static func parseEntry(_ line: String) -> GitConfigEntry? {
        // Split on first = sign
        guard let equalsIndex = line.firstIndex(of: "=") else {
            // Bare key (no value) — treated as key = ""
            let key = line.trimmed
            guard !key.isEmpty else { return nil }
            return GitConfigEntry(key: key, value: "")
        }

        let key = String(line[line.startIndex..<equalsIndex]).trimmed
        var value = String(line[line.index(after: equalsIndex)...]).trimmed

        guard !key.isEmpty else { return nil }

        // Strip inline comments (# or ; not inside quotes)
        value = stripInlineComment(value)

        return GitConfigEntry(key: key, value: value)
    }

    /// Strips inline comments from a value string, respecting quoted strings
    private static func stripInlineComment(_ value: String) -> String {
        var inQuote = false
        var quoteChar: Character = "\""
        var result: [Character] = []

        for char in value {
            if !inQuote && (char == "#" || char == ";") {
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

    private static func sectionKey(name: String, subsection: String?) -> String {
        if let subsection {
            return "\(name)|\(subsection)"
        }
        return name
    }
}
