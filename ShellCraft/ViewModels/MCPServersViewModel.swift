import Foundation

@MainActor @Observable
final class MCPServersViewModel {

    // MARK: - Properties

    var servers: [MCPServer] = []
    var hasUnsavedChanges = false

    private var originalServers: [MCPServer] = []

    // MARK: - Computed

    var serverCount: Int { servers.count }

    var serversByTransport: [(transport: MCPServer.Transport, servers: [MCPServer])] {
        let grouped = Dictionary(grouping: servers, by: \.transport)
        return MCPServer.Transport.allCases.compactMap { transport in
            guard let list = grouped[transport], !list.isEmpty else { return nil }
            return (transport: transport, servers: list)
        }
    }

    // MARK: - Load

    func load(from mcpConfig: [String: MCPServerConfig]) {
        servers = ClaudeSettingsService.mcpServers(from: mcpConfig)
        originalServers = servers
        hasUnsavedChanges = false
    }

    /// Loads from both ~/.mcp.json and ~/.claude.json, merging by name.
    func load(mcpJson: [String: MCPServerConfig], claudeJson: [String: MCPServerConfig]) {
        var merged = ClaudeSettingsService.mcpServers(from: mcpJson, source: .mcpJson)
        let fromClaude = ClaudeSettingsService.mcpServers(from: claudeJson, source: .claudeJson)
        let existingNames = Set(merged.map(\.name))
        for server in fromClaude where !existingNames.contains(server.name) {
            merged.append(server)
        }
        servers = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        originalServers = servers
        hasUnsavedChanges = false
    }

    // MARK: - Convert Back

    /// Returns configs split by source for saving to the correct file.
    func toConfigBySource() -> (mcpJson: [String: MCPServerConfig], claudeJson: [String: MCPServerConfig]) {
        let mcpJsonServers = servers.filter { $0.source == .mcpJson }
        let claudeJsonServers = servers.filter { $0.source == .claudeJson }
        return (
            mcpJson: ClaudeSettingsService.mcpServerConfigs(from: mcpJsonServers),
            claudeJson: ClaudeSettingsService.mcpServerConfigs(from: claudeJsonServers)
        )
    }

    func toConfig() -> [String: MCPServerConfig] {
        ClaudeSettingsService.mcpServerConfigs(from: servers)
    }

    // MARK: - Mutations

    func add(_ server: MCPServer) {
        servers.append(server)
        servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        trackChanges()
    }

    func update(_ server: MCPServer) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        trackChanges()
    }

    func remove(_ server: MCPServer) {
        servers.removeAll { $0.id == server.id }
        trackChanges()
    }

    func removeByName(_ name: String) {
        servers.removeAll { $0.name == name }
        trackChanges()
    }

    // MARK: - Change Tracking

    func markSaved() {
        originalServers = servers
        hasUnsavedChanges = false
    }

    private func trackChanges() {
        if servers.count != originalServers.count {
            hasUnsavedChanges = true
            return
        }
        for (current, original) in zip(servers, originalServers) {
            if current.name != original.name ||
               current.transport != original.transport ||
               current.url != original.url ||
               current.command != original.command ||
               current.args != original.args ||
               current.env != original.env {
                hasUnsavedChanges = true
                return
            }
        }
        hasUnsavedChanges = false
    }
}
