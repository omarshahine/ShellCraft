import Foundation

enum ClaudeTab: String, CaseIterable, Identifiable {
    case general = "General"
    case permissions = "Permissions"
    case hooks = "Hooks"
    case plugins = "Plugins"
    case mcp = "MCP Servers"
    case env = "Environment"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gear"
        case .permissions: "lock.shield"
        case .hooks: "arrow.triangle.turn.up.right.diamond"
        case .plugins: "puzzlepiece.extension"
        case .mcp: "server.rack"
        case .env: "list.bullet.rectangle"
        }
    }
}

@MainActor @Observable
final class ClaudeSettingsViewModel {

    // MARK: - Properties

    var settings = ClaudeSettings()
    var selectedTab: ClaudeTab = .general
    var error: String?
    var isLoading = false

    // Sub-ViewModels
    var permissionsVM = ClaudePermissionsViewModel()
    var hooksVM = ClaudeHooksViewModel()
    var pluginsVM = ClaudePluginsViewModel()
    var mcpServersVM = MCPServersViewModel()

    // Environment variables from settings
    var envVars: [EnvEntry] = []

    private var originalSettings = ClaudeSettings()
    private var originalEnvVars: [EnvEntry] = []
    private var rawJSON: [String: Any] = [:]

    // MARK: - Computed

    var hasUnsavedChanges: Bool {
        settingsChanged ||
        permissionsVM.hasUnsavedChanges ||
        hooksVM.hasUnsavedChanges ||
        pluginsVM.hasUnsavedChanges ||
        mcpServersVM.hasUnsavedChanges ||
        envVarsChanged
    }

    private var settingsChanged: Bool {
        let modelChanged =
            settings.model != originalSettings.model ||
            settings.outputStyle != originalSettings.outputStyle ||
            settings.language != originalSettings.language
        let displayChanged =
            settings.statusLine != originalSettings.statusLine ||
            settings.attribution != originalSettings.attribution ||
            settings.showTurnDuration != originalSettings.showTurnDuration ||
            settings.terminalProgressBarEnabled != originalSettings.terminalProgressBarEnabled ||
            settings.spinnerTipsEnabled != originalSettings.spinnerTipsEnabled ||
            settings.prefersReducedMotion != originalSettings.prefersReducedMotion
        let behaviorChanged =
            settings.alwaysThinkingEnabled != originalSettings.alwaysThinkingEnabled ||
            settings.teammateMode != originalSettings.teammateMode ||
            settings.respectGitignore != originalSettings.respectGitignore ||
            settings.plansDirectory != originalSettings.plansDirectory
        let otherChanged =
            settings.skipDangerousModePermissionPrompt != originalSettings.skipDangerousModePermissionPrompt ||
            settings.cleanupPeriodDays != originalSettings.cleanupPeriodDays ||
            settings.autoUpdatesChannel != originalSettings.autoUpdatesChannel ||
            settings.disableAllHooks != originalSettings.disableAllHooks
        return modelChanged || displayChanged || behaviorChanged || otherChanged
    }

    private var envVarsChanged: Bool {
        envVars != originalEnvVars
    }

    // MARK: - Load

    func load() {
        isLoading = true
        error = nil

        do {
            let result = try ClaudeSettingsService.loadSettings()
            settings = result.settings
            rawJSON = result.rawJSON
            originalSettings = settings

            // Load sub-VM data
            permissionsVM.load(from: settings)
            hooksVM.load(from: settings)

            // Load plugins from multiple sources
            let enabledPlugins = settings.enabledPlugins ?? [:]
            let installed = (try? ClaudeSettingsService.loadInstalledPlugins()) ?? [:]
            let marketplaces = (try? ClaudeSettingsService.loadMarketplaces()) ?? [:]
            pluginsVM.load(enabledPlugins: enabledPlugins, installedPlugins: installed, marketplaces: marketplaces)

            // Load MCP servers from both ~/.mcp.json and ~/.claude.json
            let mcpSources = (try? ClaudeSettingsService.loadMCPConfig()) ?? (mcpJson: [:], claudeJson: [:])
            mcpServersVM.load(mcpJson: mcpSources.mcpJson, claudeJson: mcpSources.claudeJson)

            // Load env vars
            envVars = (settings.env ?? [:]).map { EnvEntry(key: $0.key, value: $0.value) }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            originalEnvVars = envVars

        } catch {
            self.error = "Failed to load Claude settings: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Save

    func save() {
        error = nil

        do {
            // Merge sub-VM data back into settings
            settings.permissions = permissionsVM.toSettings()
            settings.hooks = hooksVM.toSettings()
            settings.enabledPlugins = pluginsVM.toEnabledPlugins()

            // Merge env vars
            if envVars.isEmpty {
                settings.env = nil
            } else {
                var env: [String: String] = [:]
                for entry in envVars where !entry.key.isEmpty {
                    env[entry.key] = entry.value
                }
                settings.env = env.isEmpty ? nil : env
            }

            try ClaudeSettingsService.saveSettings(settings, rawJSON: rawJSON)

            // Re-read rawJSON from disk to stay in sync
            let result = try ClaudeSettingsService.loadSettings()
            rawJSON = result.rawJSON

            originalSettings = settings
            originalEnvVars = envVars

            // Save MCP config — split by source to write to the correct file
            let mcpBySource = mcpServersVM.toConfigBySource()
            try ClaudeSettingsService.saveMCPConfig(mcpBySource.mcpJson)
            try ClaudeSettingsService.saveClaudeJsonMCPConfig(mcpBySource.claudeJson)

            // Reset change tracking on sub-VMs
            permissionsVM.markSaved()
            hooksVM.markSaved()
            pluginsVM.markSaved()
            mcpServersVM.markSaved()

        } catch {
            self.error = "Failed to save Claude settings: \(error.localizedDescription)"
        }
    }

    // MARK: - Discard

    func discard() {
        settings = originalSettings
        envVars = originalEnvVars
        permissionsVM.load(from: originalSettings)
        hooksVM.load(from: originalSettings)

        let enabledPlugins = originalSettings.enabledPlugins ?? [:]
        let installed = (try? ClaudeSettingsService.loadInstalledPlugins()) ?? [:]
        let marketplaces = (try? ClaudeSettingsService.loadMarketplaces()) ?? [:]
        pluginsVM.load(enabledPlugins: enabledPlugins, installedPlugins: installed, marketplaces: marketplaces)

        let mcpSources = (try? ClaudeSettingsService.loadMCPConfig()) ?? (mcpJson: [:], claudeJson: [:])
        mcpServersVM.load(mcpJson: mcpSources.mcpJson, claudeJson: mcpSources.claudeJson)
    }

    // MARK: - Env Var Operations

    func addEnvVar() {
        envVars.append(EnvEntry(key: "", value: ""))
    }

    func removeEnvVar(_ entry: EnvEntry) {
        envVars.removeAll { $0.id == entry.id }
    }

    // MARK: - Import / Export

    func exportData() -> String {
        // Merge typed settings into rawJSON for round-trip safe export
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let typedData = try encoder.encode(settings)
            guard let typedDict = try JSONSerialization.jsonObject(with: typedData) as? [String: Any] else {
                return "{}"
            }
            var merged = rawJSON
            for key in ClaudeSettings.allCodingKeyStrings {
                if let value = typedDict[key] {
                    merged[key] = value
                } else {
                    merged.removeValue(forKey: key)
                }
            }
            let data = try JSONSerialization.data(
                withJSONObject: merged,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    func previewImport(_ content: String) -> ImportPreview {
        ImportPreview(
            fileName: "",
            sectionName: "Claude Code Settings",
            isReplace: true,
            newItems: [],
            updatedItems: [],
            unchangedCount: 0,
            warnings: ["This will replace your current Claude Code settings."]
        )
    }

    func applyImport(_ content: String) {
        guard let data = content.data(using: .utf8),
              let imported = try? JSONDecoder().decode(ClaudeSettings.self, from: data) else {
            error = "Failed to parse imported Claude settings JSON."
            return
        }

        // Capture raw JSON from import for round-trip safety
        if let importedRaw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rawJSON = importedRaw
        }

        settings = imported

        // Reload sub-VMs from the new settings
        permissionsVM.load(from: settings)
        hooksVM.load(from: settings)

        let enabledPlugins = settings.enabledPlugins ?? [:]
        let installed = (try? ClaudeSettingsService.loadInstalledPlugins()) ?? [:]
        let marketplaces = (try? ClaudeSettingsService.loadMarketplaces()) ?? [:]
        pluginsVM.load(enabledPlugins: enabledPlugins, installedPlugins: installed, marketplaces: marketplaces)

        envVars = (settings.env ?? [:]).map { EnvEntry(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
}

// MARK: - Env Entry

struct EnvEntry: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}
