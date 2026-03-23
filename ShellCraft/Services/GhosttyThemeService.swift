import Foundation

/// Loads and parses Ghostty's bundled theme files from the app bundle.
struct GhosttyThemeService {

    static let themesDirectory = "/Applications/Ghostty.app/Contents/Resources/ghostty/themes"

    // MARK: - Theme Discovery

    /// Returns a sorted list of all available theme names.
    static func loadThemeNames() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: themesDirectory) else {
            return []
        }
        return files.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Theme Parsing

    /// Parses a single theme file by name.
    static func parseTheme(named name: String) -> GhosttyTheme? {
        let path = (themesDirectory as NSString).appendingPathComponent(name)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return parseTheme(content: content, name: name)
    }

    /// Parses theme content into a GhosttyTheme.
    static func parseTheme(content: String, name: String) -> GhosttyTheme {
        var theme = GhosttyTheme(name: name)

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<equalsIndex]
                .trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":
                theme.background = value
            case "foreground":
                theme.foreground = value
            case "cursor-color":
                theme.cursorColor = value
            case "cursor-text":
                theme.cursorText = value
            case "selection-background":
                theme.selectionBackground = value
            case "selection-foreground":
                theme.selectionForeground = value
            case "palette":
                // Format: "N=#hex"
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2,
                   let index = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                    theme.palette[index] = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            default:
                break
            }
        }

        return theme
    }

    /// Parses all bundled themes. Designed to be called from a background Task.
    static func parseAllThemes() -> [GhosttyTheme] {
        let names = loadThemeNames()
        return names.compactMap { parseTheme(named: $0) }
    }
}
