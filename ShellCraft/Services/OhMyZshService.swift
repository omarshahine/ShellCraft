import Foundation

struct OhMyZshService {

    static let omzPath = "~/.oh-my-zsh"
    static let zshrcPath = "~/.zshrc"

    // MARK: - Installation Check

    static func isInstalled() -> Bool {
        FileIOService.fileExists(at: omzPath)
    }

    // MARK: - Filesystem Scanning

    /// Scans bundled + custom themes from ~/.oh-my-zsh/themes/ and custom/themes/
    static func scanThemes() -> [OhMyZshTheme] {
        let fm = FileManager.default
        let basePath = omzPath.expandingTildeInPath
        var themes: [OhMyZshTheme] = []

        // Bundled themes
        let themesDir = basePath + "/themes"
        if let files = try? fm.contentsOfDirectory(atPath: themesDir) {
            for file in files where file.hasSuffix(".zsh-theme") {
                let name = String(file.dropLast(".zsh-theme".count))
                themes.append(OhMyZshTheme(name: name, isCustom: false))
            }
        }

        // Custom themes
        let customThemesDir = basePath + "/custom/themes"
        if let files = try? fm.contentsOfDirectory(atPath: customThemesDir) {
            for file in files where file.hasSuffix(".zsh-theme") {
                let name = String(file.dropLast(".zsh-theme".count))
                // Skip if already present (custom overrides bundled)
                if !themes.contains(where: { $0.name == name }) {
                    themes.append(OhMyZshTheme(name: name, isCustom: true))
                }
            }
        }

        return themes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Scans plugin directory names from bundled + custom plugins
    static func scanPluginNames() -> [(name: String, isCustom: Bool)] {
        let fm = FileManager.default
        let basePath = omzPath.expandingTildeInPath
        var plugins: [(name: String, isCustom: Bool)] = []
        var seen = Set<String>()

        // Custom plugins first (take priority)
        let customPluginsDir = basePath + "/custom/plugins"
        if let dirs = try? fm.contentsOfDirectory(atPath: customPluginsDir) {
            for dir in dirs {
                let fullPath = customPluginsDir + "/" + dir
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue,
                   !dir.hasPrefix(".") {
                    plugins.append((name: dir, isCustom: true))
                    seen.insert(dir)
                }
            }
        }

        // Bundled plugins
        let pluginsDir = basePath + "/plugins"
        if let dirs = try? fm.contentsOfDirectory(atPath: pluginsDir) {
            for dir in dirs {
                let fullPath = pluginsDir + "/" + dir
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue,
                   !dir.hasPrefix("."), !seen.contains(dir) {
                    plugins.append((name: dir, isCustom: false))
                }
            }
        }

        return plugins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads the first content paragraph from a plugin's README.md
    static func loadPluginDescription(name: String) -> String {
        let basePath = omzPath.expandingTildeInPath

        // Try custom first, then bundled
        let paths = [
            basePath + "/custom/plugins/\(name)/README.md",
            basePath + "/plugins/\(name)/README.md",
        ]

        for path in paths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")

            // Skip title line (# ...) and blank lines, return first content paragraph
            var foundTitle = false
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    foundTitle = true
                    continue
                }
                if foundTitle && trimmed.isEmpty {
                    continue
                }
                if foundTitle && !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("![") {
                    // Strip markdown links for cleaner display
                    let cleaned = trimmed
                        .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
                    return String(cleaned.prefix(200))
                }
            }

            return ""
        }

        return ""
    }

    // MARK: - .zshrc Parsing

    /// Parses ZSH_THEME="..." from .zshrc lines
    static func parseTheme(from lines: [String]) -> (name: String, lineNumber: Int)? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match: ZSH_THEME="theme_name" (not commented out)
            if let match = trimmed.wholeMatch(of: /^ZSH_THEME=["']([^"']*)["']$/) {
                return (name: String(match.1), lineNumber: index + 1)
            }
        }
        return nil
    }

    /// Parses plugins=(...) from .zshrc lines, handling single and multiline formats
    static func parsePlugins(from lines: [String]) -> (names: [String], lineNumber: Int)? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match: plugins=(...)
            if trimmed.hasPrefix("plugins=(") {
                // Single line: plugins=(git autojump ...)
                if trimmed.hasSuffix(")") {
                    let inner = trimmed
                        .dropFirst("plugins=(".count)
                        .dropLast(1)
                    let names = String(inner)
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }
                    return (names: names, lineNumber: index + 1)
                }

                // Multiline: collect until closing )
                var inner = String(trimmed.dropFirst("plugins=(".count))
                var lineIdx = index + 1
                while lineIdx < lines.count {
                    let nextLine = lines[lineIdx].trimmingCharacters(in: .whitespaces)
                    if nextLine.contains(")") {
                        inner += " " + nextLine.replacingOccurrences(of: ")", with: "")
                        break
                    }
                    inner += " " + nextLine
                    lineIdx += 1
                }
                let names = inner
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                return (names: names, lineNumber: index + 1)
            }
        }
        return nil
    }

    /// Parses known OMZ settings from .zshrc, including commented-out ones
    static func parseSettings(from lines: [String]) -> [OhMyZshSetting] {
        var settings: [OhMyZshSetting] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match active: KEY="value" or KEY=value
            for known in OhMyZshSetting.knownSettings {
                let key = known.key

                // Active line: CASE_SENSITIVE="true"
                if let match = trimmed.wholeMatch(of: try! Regex("^\(key)=[\"']?([^\"']*)[\"']?$")) {
                    let value = String(match.output[1].substring ?? "")
                    settings.append(OhMyZshSetting(
                        key: key,
                        value: value,
                        description: known.description,
                        isEnabled: true,
                        lineNumber: index + 1
                    ))
                    break
                }

                // Commented-out line: # CASE_SENSITIVE="true"
                if let match = trimmed.wholeMatch(of: try! Regex("^#\\s*\(key)=[\"']?([^\"']*)[\"']?$")) {
                    let value = String(match.output[1].substring ?? "")
                    settings.append(OhMyZshSetting(
                        key: key,
                        value: value,
                        description: known.description,
                        isEnabled: false,
                        lineNumber: index + 1
                    ))
                    break
                }
            }
        }

        // Add any known settings not found in .zshrc (they can be appended on save if enabled)
        let foundKeys = Set(settings.map(\.key))
        for known in OhMyZshSetting.knownSettings where !foundKeys.contains(known.key) {
            settings.append(OhMyZshSetting(
                key: known.key,
                value: known.defaultValue,
                description: known.description,
                isEnabled: false,
                lineNumber: 0 // not present in file
            ))
        }

        return settings
    }

    // MARK: - Modification Generation

    /// Generates a modification to change the ZSH_THEME line
    static func themeModification(newTheme: String, lineNumber: Int) -> ShellConfigWriter.Modification {
        .updateLine(lineNumber - 1, "ZSH_THEME=\"\(newTheme)\"")
    }

    /// Generates a modification to rewrite the plugins=(...) line
    static func pluginsModification(enabledPlugins: [String], lineNumber: Int) -> ShellConfigWriter.Modification {
        let pluginList = enabledPlugins.joined(separator: " ")
        return .updateLine(lineNumber - 1, "plugins=(\(pluginList))")
    }

    /// Generates a modification to update a setting line (toggle comment or change value)
    static func settingModification(setting: OhMyZshSetting) -> ShellConfigWriter.Modification {
        if setting.lineNumber > 0 {
            // Update existing line
            let line: String
            if setting.isEnabled {
                line = "\(setting.key)=\"\(setting.value)\""
            } else {
                line = "# \(setting.key)=\"\(setting.value)\""
            }
            return .updateLine(setting.lineNumber - 1, line)
        } else {
            // Setting not in file — append it
            let line: String
            if setting.isEnabled {
                line = "\(setting.key)=\"\(setting.value)\""
            } else {
                line = "# \(setting.key)=\"\(setting.value)\""
            }
            return .appendLine(line)
        }
    }
}
