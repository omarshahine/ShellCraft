import Foundation

struct OhMyZshSetting: Identifiable {
    let key: String
    var value: String
    let description: String
    var isEnabled: Bool
    var lineNumber: Int

    var id: String { key }

    /// Whether this setting takes a freeform string value (vs. a boolean toggle)
    var isStringValue: Bool {
        switch key {
        case "HIST_STAMPS", "COMPLETION_WAITING_DOTS", "ZSH_THEME_RANDOM_CANDIDATES":
            return true
        default:
            return false
        }
    }

    /// All recognized Oh My Zsh settings with their descriptions.
    static let knownSettings: [(key: String, description: String, defaultValue: String)] = [
        ("CASE_SENSITIVE", "Case-sensitive completion", "true"),
        ("HYPHEN_INSENSITIVE", "Hyphen-insensitive completion (requires case-insensitive on)", "true"),
        ("DISABLE_MAGIC_FUNCTIONS", "Disable magic functions for pasted URLs/brackets", "true"),
        ("DISABLE_LS_COLORS", "Disable colors in ls output", "true"),
        ("DISABLE_AUTO_TITLE", "Disable auto-setting terminal title", "true"),
        ("ENABLE_CORRECTION", "Enable command auto-correction", "true"),
        ("COMPLETION_WAITING_DOTS", "Display dots while waiting for completion", "true"),
        ("DISABLE_UNTRACKED_FILES_DIRTY", "Faster repo status check (ignores untracked files)", "true"),
        ("HIST_STAMPS", "History command timestamp format", "mm/dd/yyyy"),
        ("ZSH_THEME_RANDOM_CANDIDATES", "Themes to choose from in random mode", "( robbyrussell agnoster )"),
    ]

    /// Returns the known setting keys for quick lookup
    static let knownKeys: Set<String> = Set(knownSettings.map(\.key))
}
