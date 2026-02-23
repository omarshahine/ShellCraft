import Foundation

@MainActor @Observable
final class ClaudePluginsViewModel {

    // MARK: - Properties

    var plugins: [ClaudePlugin] = []
    var hasUnsavedChanges = false

    private var originalPlugins: [ClaudePlugin] = []

    // MARK: - Computed

    var enabledCount: Int {
        plugins.count { $0.enabled }
    }

    var disabledCount: Int {
        plugins.count { !$0.enabled }
    }

    var pluginsByMarketplace: [(marketplace: String, plugins: [ClaudePlugin])] {
        let grouped = Dictionary(grouping: plugins, by: \.marketplace)
        return grouped.keys.sorted().map { key in
            (marketplace: key, plugins: grouped[key] ?? [])
        }
    }

    // MARK: - Load

    func load(
        enabledPlugins: [String: Bool],
        installedPlugins: [String: InstalledPluginInfo],
        marketplaces: [String: MarketplaceInfo]
    ) {
        plugins = ClaudeSettingsService.mergePlugins(
            enabledPlugins: enabledPlugins,
            installedPlugins: installedPlugins,
            marketplaces: marketplaces
        )
        originalPlugins = plugins
        hasUnsavedChanges = false
    }

    // MARK: - Convert Back

    func toEnabledPlugins() -> [String: Bool]? {
        var result: [String: Bool] = [:]
        for plugin in plugins {
            result[plugin.qualifiedName] = plugin.enabled
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Mutations

    func toggle(_ plugin: ClaudePlugin) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[index].enabled.toggle()
        trackChanges()
    }

    func remove(_ plugin: ClaudePlugin) {
        plugins.removeAll { $0.id == plugin.id }
        trackChanges()
    }

    // MARK: - Change Tracking

    func markSaved() {
        originalPlugins = plugins
        hasUnsavedChanges = false
    }

    private func trackChanges() {
        if plugins.count != originalPlugins.count {
            hasUnsavedChanges = true
            return
        }
        for (current, original) in zip(plugins, originalPlugins) {
            if current.qualifiedName != original.qualifiedName || current.enabled != original.enabled {
                hasUnsavedChanges = true
                return
            }
        }
        hasUnsavedChanges = false
    }
}
