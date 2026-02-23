import Foundation

// MARK: - Intermediate Codable Types for JSON Shapes

/// Represents the MCP config JSON shape in ~/.mcp.json
/// The top-level object has a "mcpServers" key containing server configs.
struct MCPConfigFile: Codable {
    var mcpServers: [String: MCPServerConfig]

    init(mcpServers: [String: MCPServerConfig] = [:]) {
        self.mcpServers = mcpServers
    }
}

/// A single MCP server configuration supporting both stdio and http transports.
struct MCPServerConfig: Codable {
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: String?
    var transport: String?

    /// Determines transport type from the config shape.
    var inferredTransport: MCPServer.Transport {
        if let transport {
            switch transport.lowercased() {
            case "http": return .http
            case "sse": return .sse
            default: return .stdio
            }
        }
        if url != nil && command == nil {
            return .http
        }
        return .stdio
    }
}

/// Plugin info from installed_plugins.json — each key is "plugin@marketplace"
struct InstalledPluginInfo: Codable {
    var version: String?
    var installedAt: String?
    var marketplace: String?
}

/// Marketplace info from known_marketplaces.json — each key is marketplace name, value is path
struct MarketplaceInfo: Codable {
    var path: String?
    var type: String?
}

// MARK: - Service

struct ClaudeSettingsService {

    // MARK: - File Paths

    static let settingsPath = "~/.claude/settings.json"
    static let mcpConfigPath = "~/.mcp.json"
    static let installedPluginsPath = "~/.claude/plugins/installed_plugins.json"
    static let marketplacesPath = "~/.claude/plugins/known_marketplaces.json"

    // MARK: - Settings

    static func loadSettings() throws -> (settings: ClaudeSettings, rawJSON: [String: Any]) {
        guard FileIOService.fileExists(at: settingsPath) else {
            return (ClaudeSettings(), [:])
        }
        let content = try FileIOService.readFile(at: settingsPath)
        guard let data = content.data(using: .utf8) else {
            return (ClaudeSettings(), [:])
        }
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)
        let rawJSON = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (settings, rawJSON)
    }

    static func saveSettings(_ settings: ClaudeSettings, rawJSON: [String: Any]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let typedData = try encoder.encode(settings)
        guard let typedDict = try JSONSerialization.jsonObject(with: typedData) as? [String: Any] else {
            throw ClaudeSettingsError.encodingFailed
        }

        // Start with raw JSON (preserves unknown keys like sandbox)
        var merged = rawJSON
        for key in ClaudeSettings.allCodingKeyStrings {
            if let value = typedDict[key] {
                merged[key] = value
            } else {
                merged.removeValue(forKey: key)
            }
        }

        let mergedData = try JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let content = String(data: mergedData, encoding: .utf8) else {
            throw ClaudeSettingsError.encodingFailed
        }
        try FileIOService.writeFile(at: settingsPath, content: content + "\n")
    }

    // MARK: - MCP Config

    /// The user-level Claude config that may also contain MCP servers.
    static let claudeJsonPath = "~/.claude.json"

    /// Loads MCP server configs from both ~/.mcp.json and ~/.claude.json, tagged by source.
    static func loadMCPConfig() throws -> (mcpJson: [String: MCPServerConfig], claudeJson: [String: MCPServerConfig]) {
        var mcpJsonServers: [String: MCPServerConfig] = [:]
        var claudeJsonServers: [String: MCPServerConfig] = [:]

        // Read from ~/.mcp.json
        if FileIOService.fileExists(at: mcpConfigPath) {
            let content = try FileIOService.readFile(at: mcpConfigPath)
            if let data = content.data(using: .utf8) {
                let config = try JSONDecoder().decode(MCPConfigFile.self, from: data)
                mcpJsonServers = config.mcpServers
            }
        }

        // Read from ~/.claude.json (mcpServers key)
        if FileIOService.fileExists(at: claudeJsonPath) {
            let content = try FileIOService.readFile(at: claudeJsonPath)
            if let data = content.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serversDict = json["mcpServers"] as? [String: Any] {
                let serversData = try JSONSerialization.data(withJSONObject: serversDict)
                claudeJsonServers = try JSONDecoder().decode([String: MCPServerConfig].self, from: serversData)
            }
        }

        return (mcpJson: mcpJsonServers, claudeJson: claudeJsonServers)
    }

    /// Saves MCP servers back to ~/.mcp.json only (for servers sourced from ~/.mcp.json or newly added).
    static func saveMCPConfig(_ servers: [String: MCPServerConfig]) throws {
        let config = MCPConfigFile(mcpServers: servers)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ClaudeSettingsError.encodingFailed
        }
        try FileIOService.writeFile(at: mcpConfigPath, content: content + "\n")
    }

    /// Saves MCP servers back to ~/.claude.json, updating only the mcpServers key.
    static func saveClaudeJsonMCPConfig(_ servers: [String: MCPServerConfig]) throws {
        guard FileIOService.fileExists(at: claudeJsonPath) else { return }
        let expandedPath = claudeJsonPath.expandingTildeInPath
        let content = try FileIOService.readFile(at: claudeJsonPath)
        guard let data = content.data(using: .utf8),
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Re-encode just the servers into JSON-compatible dictionaries
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let serversData = try encoder.encode(servers)
        let serversObj = try JSONSerialization.jsonObject(with: serversData)

        json["mcpServers"] = serversObj

        let updatedData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let updatedContent = String(data: updatedData, encoding: .utf8) else {
            throw ClaudeSettingsError.encodingFailed
        }
        // Write directly without backup (claude.json is managed by Claude Code)
        try updatedContent.write(toFile: expandedPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Plugins

    static func loadInstalledPlugins() throws -> [String: InstalledPluginInfo] {
        guard FileIOService.fileExists(at: installedPluginsPath) else {
            return [:]
        }
        let content = try FileIOService.readFile(at: installedPluginsPath)
        guard let data = content.data(using: .utf8) else {
            return [:]
        }
        let decoder = JSONDecoder()
        return try decoder.decode([String: InstalledPluginInfo].self, from: data)
    }

    // MARK: - Marketplaces

    static func loadMarketplaces() throws -> [String: MarketplaceInfo] {
        guard FileIOService.fileExists(at: marketplacesPath) else {
            return [:]
        }
        let content = try FileIOService.readFile(at: marketplacesPath)
        guard let data = content.data(using: .utf8) else {
            return [:]
        }
        let decoder = JSONDecoder()

        // The marketplaces JSON can be either { "name": "/path" } or { "name": { "path": "...", "type": "..." } }
        // Try as [String: MarketplaceInfo] first, then fall back to [String: String]
        if let typed = try? decoder.decode([String: MarketplaceInfo].self, from: data) {
            return typed
        }

        // Fall back: simple string values (marketplace name -> path)
        if let simple = try? decoder.decode([String: String].self, from: data) {
            return simple.mapValues { MarketplaceInfo(path: $0, type: nil) }
        }

        return [:]
    }

    // MARK: - Conversion Helpers

    /// Converts raw MCP server configs into MCPServer model objects.
    static func mcpServers(from configs: [String: MCPServerConfig], source: MCPServer.Source = .mcpJson) -> [MCPServer] {
        configs.map { name, config in
            MCPServer(
                name: name,
                transport: config.inferredTransport,
                url: config.url ?? "",
                command: config.command ?? "",
                args: config.args ?? [],
                env: config.env ?? [:],
                source: source
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Converts MCPServer model objects back into raw configs for serialization.
    static func mcpServerConfigs(from servers: [MCPServer]) -> [String: MCPServerConfig] {
        var result: [String: MCPServerConfig] = [:]
        for server in servers {
            var config = MCPServerConfig()
            switch server.transport {
            case .stdio:
                config.command = server.command
                if !server.args.isEmpty {
                    config.args = server.args
                }
                if !server.env.isEmpty {
                    config.env = server.env
                }
            case .http:
                config.url = server.url
                config.transport = "http"
                if !server.env.isEmpty {
                    config.env = server.env
                }
            case .sse:
                config.url = server.url
                config.transport = "sse"
                if !server.env.isEmpty {
                    config.env = server.env
                }
            }
            result[server.name] = config
        }
        return result
    }

    /// Merges installed plugins, enabled state, and marketplace data into ClaudePlugin models.
    static func mergePlugins(
        enabledPlugins: [String: Bool],
        installedPlugins: [String: InstalledPluginInfo],
        marketplaces: [String: MarketplaceInfo]
    ) -> [ClaudePlugin] {
        var plugins: [ClaudePlugin] = []
        var seen: Set<String> = []

        // Process installed plugins (authoritative source)
        for (qualifiedName, info) in installedPlugins {
            seen.insert(qualifiedName)
            let parts = qualifiedName.split(separator: "@", maxSplits: 1)
            let name = parts.count > 0 ? String(parts[0]) : qualifiedName
            let marketplace = parts.count > 1 ? String(parts[1]) : (info.marketplace ?? "unknown")
            let enabled = enabledPlugins[qualifiedName] ?? true
            plugins.append(ClaudePlugin(
                name: name,
                marketplace: marketplace,
                enabled: enabled,
                version: info.version
            ))
        }

        // Add any plugins in enabledPlugins that aren't installed (stale references)
        for (qualifiedName, enabled) in enabledPlugins where !seen.contains(qualifiedName) {
            let parts = qualifiedName.split(separator: "@", maxSplits: 1)
            let name = parts.count > 0 ? String(parts[0]) : qualifiedName
            let marketplace = parts.count > 1 ? String(parts[1]) : "unknown"
            plugins.append(ClaudePlugin(
                name: name,
                marketplace: marketplace,
                enabled: enabled
            ))
        }

        return plugins.sorted {
            ($0.marketplace, $0.name) < ($1.marketplace, $1.name)
        }
    }
}

// MARK: - Errors

enum ClaudeSettingsError: LocalizedError {
    case encodingFailed
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode settings to JSON"
        case .decodingFailed(let detail):
            "Failed to decode settings: \(detail)"
        }
    }
}
