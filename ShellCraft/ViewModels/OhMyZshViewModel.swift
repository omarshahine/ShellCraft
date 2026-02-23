import Foundation
import UniformTypeIdentifiers

enum OhMyZshTab: String, CaseIterable, Identifiable {
    case themes = "Themes"
    case plugins = "Plugins"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .themes: "paintpalette"
        case .plugins: "puzzlepiece.extension"
        case .settings: "gearshape"
        }
    }
}

@MainActor @Observable
final class OhMyZshViewModel {

    // MARK: - State

    var isInstalled = false
    var isLoading = false
    var error: String?
    var searchText = ""
    var selectedTab: OhMyZshTab = .themes

    // MARK: - Data

    var themes: [OhMyZshTheme] = []
    var currentTheme: String = ""
    var plugins: [OhMyZshPlugin] = []
    var settings: [OhMyZshSetting] = []

    // MARK: - Dirty Tracking

    var hasUnsavedChanges = false

    // MARK: - Private State

    private var originalTheme: String = ""
    private var originalEnabledPlugins: Set<String> = []
    private var originalSettings: [String: (value: String, isEnabled: Bool)] = [:]
    private var rawLines: [String] = []
    private var themeLineNumber: Int = 0
    private var pluginsLineNumber: Int = 0
    private var descriptionTask: Task<Void, Never>?

    // MARK: - Computed

    var filteredThemes: [OhMyZshTheme] {
        guard !searchText.isEmpty else { return themes }
        return themes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredPlugins: [OhMyZshPlugin] {
        guard !searchText.isEmpty else { return plugins }
        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var enabledPlugins: [OhMyZshPlugin] {
        filteredPlugins.filter(\.isEnabled)
    }

    var disabledPlugins: [OhMyZshPlugin] {
        filteredPlugins.filter { !$0.isEnabled }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        error = nil

        isInstalled = OhMyZshService.isInstalled()
        guard isInstalled else {
            isLoading = false
            return
        }

        // Scan filesystem for themes and plugins
        themes = OhMyZshService.scanThemes()
        let scannedPlugins = OhMyZshService.scanPluginNames()

        // Parse .zshrc
        do {
            rawLines = try FileIOService.readLines(at: OhMyZshService.zshrcPath)

            // Theme
            if let parsed = OhMyZshService.parseTheme(from: rawLines) {
                currentTheme = parsed.name
                themeLineNumber = parsed.lineNumber
            }

            // Plugins
            var enabledSet = Set<String>()
            if let parsed = OhMyZshService.parsePlugins(from: rawLines) {
                enabledSet = Set(parsed.names)
                pluginsLineNumber = parsed.lineNumber
            }

            // Build plugin models
            plugins = scannedPlugins.map { info in
                OhMyZshPlugin(
                    name: info.name,
                    description: "",
                    isEnabled: enabledSet.contains(info.name),
                    isCustom: info.isCustom
                )
            }

            // Settings
            settings = OhMyZshService.parseSettings(from: rawLines)

            // Save originals for dirty tracking
            originalTheme = currentTheme
            originalEnabledPlugins = enabledSet
            originalSettings = Dictionary(uniqueKeysWithValues: settings.map {
                ($0.key, (value: $0.value, isEnabled: $0.isEnabled))
            })
        } catch {
            self.error = "Failed to read .zshrc: \(error.localizedDescription)"
        }

        isLoading = false

        // Load plugin descriptions in background
        loadDescriptions()
    }

    // MARK: - Save

    func save() {
        error = nil

        do {
            var modifications: [ShellConfigWriter.Modification] = []

            // Theme change
            if currentTheme != originalTheme && themeLineNumber > 0 {
                modifications.append(
                    OhMyZshService.themeModification(newTheme: currentTheme, lineNumber: themeLineNumber)
                )
            }

            // Plugins change
            let currentEnabled = plugins.filter(\.isEnabled).map(\.name)
            let currentEnabledSet = Set(currentEnabled)
            if currentEnabledSet != originalEnabledPlugins && pluginsLineNumber > 0 {
                modifications.append(
                    OhMyZshService.pluginsModification(enabledPlugins: currentEnabled, lineNumber: pluginsLineNumber)
                )
            }

            // Settings changes
            for setting in settings {
                if let original = originalSettings[setting.key] {
                    if setting.value != original.value || setting.isEnabled != original.isEnabled {
                        modifications.append(OhMyZshService.settingModification(setting: setting))
                    }
                }
            }

            guard !modifications.isEmpty else { return }

            let updatedLines = ShellConfigWriter.apply(modifications: modifications, to: rawLines)
            try ShellConfigWriter.writeLines(updatedLines, to: OhMyZshService.zshrcPath)

            // Reload to get fresh line numbers
            load()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Discard

    func discard() {
        currentTheme = originalTheme
        for i in plugins.indices {
            plugins[i].isEnabled = originalEnabledPlugins.contains(plugins[i].name)
        }
        for i in settings.indices {
            if let original = originalSettings[settings[i].key] {
                settings[i].value = original.value
                settings[i].isEnabled = original.isEnabled
            }
        }
        hasUnsavedChanges = false
    }

    // MARK: - Theme Actions

    func setTheme(_ name: String) {
        currentTheme = name
        updateDirtyState()
    }

    // MARK: - Plugin Actions

    func togglePlugin(_ plugin: OhMyZshPlugin) {
        guard let index = plugins.firstIndex(where: { $0.name == plugin.name }) else { return }
        plugins[index].isEnabled.toggle()
        updateDirtyState()
    }

    // MARK: - Setting Actions

    func toggleSetting(_ setting: OhMyZshSetting) {
        guard let index = settings.firstIndex(where: { $0.key == setting.key }) else { return }
        settings[index].isEnabled.toggle()
        updateDirtyState()
    }

    func updateSettingValue(_ setting: OhMyZshSetting, value: String) {
        guard let index = settings.firstIndex(where: { $0.key == setting.key }) else { return }
        settings[index].value = value
        updateDirtyState()
    }

    // MARK: - Import / Export

    func exportData() -> String {
        var output = ImportExportService.shellHeader(section: "Oh My Zsh")
        output += "ZSH_THEME=\"\(currentTheme)\"\n\n"

        let enabled = plugins.filter(\.isEnabled).map(\.name)
        output += "plugins=(\(enabled.joined(separator: " ")))\n\n"

        for setting in settings where setting.isEnabled {
            output += "\(setting.key)=\"\(setting.value)\"\n"
        }
        for setting in settings where !setting.isEnabled && setting.lineNumber > 0 {
            output += "# \(setting.key)=\"\(setting.value)\"\n"
        }

        return output
    }

    func previewImport(_ content: String) -> ImportPreview {
        let lines = content.components(separatedBy: "\n")
        var newItems: [String] = []
        var updatedItems: [String] = []
        var unchanged = 0

        // Check theme
        if let parsed = OhMyZshService.parseTheme(from: lines) {
            if parsed.name != currentTheme {
                updatedItems.append("Theme: \(parsed.name)")
            } else {
                unchanged += 1
            }
        }

        // Check plugins
        if let parsed = OhMyZshService.parsePlugins(from: lines) {
            let importedSet = Set(parsed.names)
            let currentSet = Set(plugins.filter(\.isEnabled).map(\.name))
            let added = importedSet.subtracting(currentSet)
            let removed = currentSet.subtracting(importedSet)
            for name in added.sorted() { newItems.append("Plugin: \(name)") }
            for name in removed.sorted() { updatedItems.append("Disable: \(name)") }
            if added.isEmpty && removed.isEmpty { unchanged += 1 }
        }

        // Check settings
        let importedSettings = OhMyZshService.parseSettings(from: lines)
        for imported in importedSettings {
            if let current = settings.first(where: { $0.key == imported.key }) {
                if imported.value != current.value || imported.isEnabled != current.isEnabled {
                    updatedItems.append(imported.key)
                } else {
                    unchanged += 1
                }
            } else {
                newItems.append(imported.key)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "Oh My Zsh",
            isReplace: false,
            newItems: newItems,
            updatedItems: updatedItems,
            unchangedCount: unchanged,
            warnings: []
        )
    }

    func applyImport(_ content: String) {
        let lines = content.components(separatedBy: "\n")

        // Apply theme
        if let parsed = OhMyZshService.parseTheme(from: lines) {
            currentTheme = parsed.name
        }

        // Apply plugins
        if let parsed = OhMyZshService.parsePlugins(from: lines) {
            let importedSet = Set(parsed.names)
            for i in plugins.indices {
                plugins[i].isEnabled = importedSet.contains(plugins[i].name)
            }
        }

        // Apply settings
        let importedSettings = OhMyZshService.parseSettings(from: lines)
        for imported in importedSettings {
            if let index = settings.firstIndex(where: { $0.key == imported.key }) {
                settings[index].value = imported.value
                settings[index].isEnabled = imported.isEnabled
            }
        }

        updateDirtyState()
    }

    // MARK: - Private

    private func updateDirtyState() {
        var dirty = false
        if currentTheme != originalTheme { dirty = true }
        if !dirty {
            let currentEnabled = Set(plugins.filter(\.isEnabled).map(\.name))
            if currentEnabled != originalEnabledPlugins { dirty = true }
        }
        if !dirty {
            for setting in settings {
                if let original = originalSettings[setting.key] {
                    if setting.value != original.value || setting.isEnabled != original.isEnabled {
                        dirty = true
                        break
                    }
                }
            }
        }
        hasUnsavedChanges = dirty
    }

    private func loadDescriptions() {
        descriptionTask?.cancel()
        descriptionTask = Task.detached { [plugins] in
            var descriptions: [String: String] = [:]
            for plugin in plugins {
                if Task.isCancelled { return }
                let desc = OhMyZshService.loadPluginDescription(name: plugin.name)
                descriptions[plugin.name] = desc
            }
            await MainActor.run { [descriptions] in
                for i in self.plugins.indices {
                    if let desc = descriptions[self.plugins[i].name] {
                        self.plugins[i].description = desc
                    }
                }
            }
        }
    }
}
