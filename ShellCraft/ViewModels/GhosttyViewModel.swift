import Foundation

@MainActor @Observable
final class GhosttyViewModel {

    // MARK: - Known Config Keys

    /// Keys that have typed UI controls (excluded from the raw editor)
    static let knownKeys: Set<String> = [
        "theme", "font-family", "font-size",
        "cursor-style", "cursor-style-blink",
        "background-opacity", "background-blur-radius",
        "window-padding-x", "window-padding-y",
        "window-theme", "macos-titlebar-style",
        "shell-integration", "clipboard-read", "clipboard-write",
        "copy-on-select", "mouse-hide-while-typing",
        "confirm-close-surface", "auto-update",
        "window-new-tab-position"
    ]

    // MARK: - State

    var selectedTab: GhosttyTab = .theme
    var isLoading = false
    var error: String?
    var searchText = ""
    var isInstalled = false

    // Config state
    var config = GhosttyConfig()
    private var rawLines: [String] = []
    private var originalConfig = GhosttyConfig()
    private var originalRawLines: [String] = []
    private var isApplyingLive = false

    // Theme state
    var themeNames: [String] = []
    var parsedThemes: [String: GhosttyTheme] = [:]
    var isLoadingThemes = false
    var hasAutoThemeOverride = false

    // MARK: - Dirty Tracking

    var hasUnsavedChanges: Bool {
        config != originalConfig
    }

    // MARK: - Theme Properties

    var currentThemeRaw: String {
        config.value(for: "theme") ?? ""
    }

    var useAutoTheme: Bool {
        get { currentThemeRaw.contains("light:") && currentThemeRaw.contains("dark:") }
        set {
            if newValue {
                let light = lightTheme.isEmpty ? "Ghostty Default Style Light" : lightTheme
                let dark = darkTheme.isEmpty ? "Ghostty Default Style Dark" : darkTheme
                config.setValue(for: "theme", value: "light:\(light),dark:\(dark)")
            } else {
                config.setValue(for: "theme", value: darkTheme.isEmpty ? "Ghostty Default Style Dark" : darkTheme)
            }
        }
    }

    var lightTheme: String {
        get {
            guard useAutoTheme else { return "" }
            return parseAutoTheme().light
        }
        set {
            let dark = darkTheme.isEmpty ? "Ghostty Default Style Dark" : darkTheme
            config.setValue(for: "theme", value: "light:\(newValue),dark:\(dark)")
        }
    }

    var darkTheme: String {
        get {
            guard useAutoTheme else { return currentThemeRaw }
            return parseAutoTheme().dark
        }
        set {
            if useAutoTheme {
                let light = lightTheme.isEmpty ? "Ghostty Default Style Light" : lightTheme
                config.setValue(for: "theme", value: "light:\(light),dark:\(newValue)")
            } else {
                config.setValue(for: "theme", value: newValue)
            }
        }
    }

    /// Sets the theme (single mode, not auto) and live-applies to Ghostty.
    func setTheme(_ name: String) {
        if useAutoTheme {
            darkTheme = name
        } else {
            config.setValue(for: "theme", value: name)
        }
        applyLive()
    }

    private func parseAutoTheme() -> (light: String, dark: String) {
        let raw = currentThemeRaw
        var light = ""
        var dark = ""
        for part in raw.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("light:") {
                light = String(trimmed.dropFirst(6))
            } else if trimmed.hasPrefix("dark:") {
                dark = String(trimmed.dropFirst(5))
            }
        }
        return (light, dark)
    }

    // MARK: - Appearance Properties

    var fontFamily: String {
        get { config.value(for: "font-family") ?? "" }
        set { config.setValue(for: "font-family", value: newValue) }
    }

    var fontSize: Int {
        get { Int(config.value(for: "font-size") ?? "13") ?? 13 }
        set { config.setValue(for: "font-size", value: "\(newValue)") }
    }

    var cursorStyle: String {
        get { config.value(for: "cursor-style") ?? "block" }
        set { config.setValue(for: "cursor-style", value: newValue) }
    }

    var cursorBlink: Bool {
        get { config.value(for: "cursor-style-blink") != "false" }
        set { config.setValue(for: "cursor-style-blink", value: newValue ? "true" : "false") }
    }

    var backgroundOpacity: Double {
        get { Double(config.value(for: "background-opacity") ?? "1") ?? 1.0 }
        set { config.setValue(for: "background-opacity", value: String(format: "%.2f", newValue)) }
    }

    var backgroundBlur: Int {
        get { Int(config.value(for: "background-blur-radius") ?? "0") ?? 0 }
        set { config.setValue(for: "background-blur-radius", value: "\(newValue)") }
    }

    var windowPaddingX: Int {
        get { Int(config.value(for: "window-padding-x") ?? "0") ?? 0 }
        set { config.setValue(for: "window-padding-x", value: "\(newValue)") }
    }

    var windowPaddingY: Int {
        get { Int(config.value(for: "window-padding-y") ?? "0") ?? 0 }
        set { config.setValue(for: "window-padding-y", value: "\(newValue)") }
    }

    var windowTheme: String {
        get { config.value(for: "window-theme") ?? "auto" }
        set { config.setValue(for: "window-theme", value: newValue) }
    }

    var macosTitlebarStyle: String {
        get { config.value(for: "macos-titlebar-style") ?? "transparent" }
        set { config.setValue(for: "macos-titlebar-style", value: newValue) }
    }

    // MARK: - General Properties

    var shellIntegration: String {
        get { config.value(for: "shell-integration") ?? "detect" }
        set { config.setValue(for: "shell-integration", value: newValue) }
    }

    var clipboardRead: String {
        get { config.value(for: "clipboard-read") ?? "ask" }
        set { config.setValue(for: "clipboard-read", value: newValue) }
    }

    var clipboardWrite: String {
        get { config.value(for: "clipboard-write") ?? "ask" }
        set { config.setValue(for: "clipboard-write", value: newValue) }
    }

    var copyOnSelect: String {
        get { config.value(for: "copy-on-select") ?? "false" }
        set { config.setValue(for: "copy-on-select", value: newValue) }
    }

    var mouseHideWhileTyping: Bool {
        get { config.value(for: "mouse-hide-while-typing") == "true" }
        set { config.setValue(for: "mouse-hide-while-typing", value: newValue ? "true" : "false") }
    }

    var confirmCloseSurface: Bool {
        get { config.value(for: "confirm-close-surface") != "false" }
        set { config.setValue(for: "confirm-close-surface", value: newValue ? "true" : "false") }
    }

    var autoUpdate: String {
        get { config.value(for: "auto-update") ?? "check" }
        set { config.setValue(for: "auto-update", value: newValue) }
    }

    var windowNewTabPosition: String {
        get { config.value(for: "window-new-tab-position") ?? "current" }
        set { config.setValue(for: "window-new-tab-position", value: newValue) }
    }

    // MARK: - Extra Entries (for raw editor)

    var extraEntries: [GhosttyConfigEntry] {
        config.extraEntries(excluding: Self.knownKeys)
    }

    func addExtraEntry(key: String, value: String) {
        config.entries.append(GhosttyConfigEntry(key: key, value: value))
    }

    func updateExtraEntry(_ entry: GhosttyConfigEntry, key: String, value: String) {
        guard let index = config.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        config.entries[index].key = key
        config.entries[index].value = value
    }

    func deleteExtraEntry(_ entry: GhosttyConfigEntry) {
        config.entries.removeAll { $0.id == entry.id }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        error = nil

        isInstalled = GhosttyConfigService.isInstalled()
        hasAutoThemeOverride = GhosttyConfigService.autoThemeExists()

        guard isInstalled else {
            isLoading = false
            return
        }

        do {
            if GhosttyConfigService.configExists() {
                let result = try GhosttyConfigService.parse()
                config = result.config
                rawLines = result.rawLines
            } else {
                config = GhosttyConfig()
                rawLines = []
            }
            originalConfig = config
            originalRawLines = rawLines
        } catch {
            self.error = "Failed to load Ghostty config: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Save

    func save() {
        error = nil

        do {
            try GhosttyConfigService.write(config: config, rawLines: rawLines, path: GhosttyConfigService.configPath)
            // Re-read to get updated rawLines
            let result = try GhosttyConfigService.parse()
            config = result.config
            rawLines = result.rawLines
            originalConfig = config
            originalRawLines = rawLines
            GhosttyConfigService.reloadConfig()
        } catch {
            self.error = "Failed to save Ghostty config: \(error.localizedDescription)"
        }
    }

    /// Saves and reloads Ghostty without updating the "original" snapshot,
    /// so the SaveBar still shows unsaved changes relative to the last explicit Save.
    func applyLive() {
        guard !isApplyingLive else { return }
        isApplyingLive = true
        defer { isApplyingLive = false }

        do {
            try GhosttyConfigService.write(config: config, rawLines: rawLines, path: GhosttyConfigService.configPath)
            // Re-read rawLines to stay in sync with disk
            let result = try GhosttyConfigService.parse()
            config = result.config
            rawLines = result.rawLines
            GhosttyConfigService.reloadConfig()
        } catch {
            self.error = "Failed to apply config: \(error.localizedDescription)"
        }
    }

    // MARK: - Discard

    func discard() {
        config = originalConfig
        rawLines = originalRawLines
        // Write the original config back to disk and reload Ghostty
        try? GhosttyConfigService.write(config: config, rawLines: rawLines, path: GhosttyConfigService.configPath)
        GhosttyConfigService.reloadConfig()
    }

    // MARK: - Theme Loading

    func loadThemes() async {
        isLoadingThemes = true
        themeNames = GhosttyThemeService.loadThemeNames()

        let themes = await Task.detached { @Sendable in
            GhosttyThemeService.parseAllThemes()
        }.value

        var dict: [String: GhosttyTheme] = [:]
        for theme in themes {
            dict[theme.name] = theme
        }
        parsedThemes = dict
        isLoadingThemes = false
    }

    /// Themes filtered by search text.
    var filteredThemeNames: [String] {
        guard !searchText.isEmpty else { return themeNames }
        let query = searchText.lowercased()
        return themeNames.filter { $0.lowercased().contains(query) }
    }

    // MARK: - Import / Export

    func exportData() -> String {
        GhosttyConfigService.serialize(config: config)
    }

    func previewImport(_ content: String) -> ImportPreview {
        let parsed = GhosttyConfigService.parse(content: content).config
        let newKeys = parsed.entries.filter { entry in
            !config.entries.contains(where: { $0.key == entry.key })
        }.map { "\($0.key) = \($0.value)" }

        let updatedKeys = parsed.entries.filter { entry in
            if let existing = config.value(for: entry.key) {
                return existing != entry.value
            }
            return false
        }.map { "\($0.key): \(config.value(for: $0.key) ?? "") → \($0.value)" }

        let unchangedCount = parsed.entries.count - newKeys.count - updatedKeys.count

        return ImportPreview(
            fileName: "",
            sectionName: "Ghostty Configuration",
            isReplace: true,
            newItems: newKeys,
            updatedItems: updatedKeys,
            unchangedCount: max(0, unchangedCount),
            warnings: ["This will replace your current Ghostty configuration."]
        )
    }

    func applyImport(_ content: String) {
        let result = GhosttyConfigService.parse(content: content)
        config = result.config
        rawLines = result.rawLines
    }
}
