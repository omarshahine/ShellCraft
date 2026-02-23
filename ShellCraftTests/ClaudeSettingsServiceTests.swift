import XCTest
@testable import ShellCraft

final class ClaudeSettingsServiceTests: XCTestCase {

    // MARK: - Settings Decoding

    func testDecodeValidSettings() throws {
        let json = """
        {
            "model": "claude-opus-4-6",
            "outputStyle": "concise",
            "sandbox": true,
            "permissions": {
                "allow": ["Bash(git *)", "Read(*)"],
                "deny": ["Bash(rm *)"]
            },
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Bash",
                        "command": "check-safety.sh"
                    }
                ]
            },
            "enabledPlugins": {
                "chief-of-staff@my-marketplace": true,
                "travel-agent@my-marketplace": false
            },
            "env": {
                "EDITOR": "vim",
                "TERM": "xterm-256color"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.model, "claude-opus-4-6")
        XCTAssertEqual(settings.outputStyle, "concise")
        XCTAssertEqual(settings.sandbox, true)
        XCTAssertEqual(settings.permissions?.allow?.count, 2)
        XCTAssertEqual(settings.permissions?.deny?.count, 1)
        XCTAssertEqual(settings.hooks?["PreToolUse"]?.count, 1)
        XCTAssertEqual(settings.enabledPlugins?["chief-of-staff@my-marketplace"], true)
        XCTAssertEqual(settings.enabledPlugins?["travel-agent@my-marketplace"], false)
        XCTAssertEqual(settings.env?["EDITOR"], "vim")
    }

    func testDecodeEmptySettings() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertNil(settings.model)
        XCTAssertNil(settings.outputStyle)
        XCTAssertNil(settings.sandbox)
        XCTAssertNil(settings.permissions)
        XCTAssertNil(settings.hooks)
        XCTAssertNil(settings.enabledPlugins)
        XCTAssertNil(settings.env)
    }

    func testEncodingDecodingRoundTrip() throws {
        var settings = ClaudeSettings()
        settings.model = "sonnet"
        settings.sandbox = false
        settings.permissions = ClaudePermissions(
            allow: ["Bash(git *)", "Read(*)"],
            deny: ["Bash(rm *)"]
        )
        settings.env = ["MY_VAR": "my_value"]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        let decoded = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(decoded.model, "sonnet")
        XCTAssertEqual(decoded.sandbox, false)
        XCTAssertEqual(decoded.permissions?.allow, ["Bash(git *)", "Read(*)"])
        XCTAssertEqual(decoded.permissions?.deny, ["Bash(rm *)"])
        XCTAssertEqual(decoded.env?["MY_VAR"], "my_value")
    }

    func testMissingOptionalFields() throws {
        let json = """
        {
            "model": "haiku"
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.model, "haiku")
        XCTAssertNil(settings.outputStyle)
        XCTAssertNil(settings.sandbox)
        XCTAssertNil(settings.permissions)
        XCTAssertNil(settings.hooks)
        XCTAssertNil(settings.enabledPlugins)
        XCTAssertNil(settings.env)
    }

    // MARK: - Permissions Parsing

    func testPermissionsParsing() throws {
        let json = """
        {
            "permissions": {
                "allow": [
                    "Bash(git *)",
                    "Bash(gh *)",
                    "Read(*)",
                    "Edit(*)",
                    "WebFetch(*)",
                    "mcp__fastmail__*"
                ],
                "deny": [
                    "Bash(rm *)",
                    "Bash(sudo *)"
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.permissions?.allow?.count, 6)
        XCTAssertEqual(settings.permissions?.deny?.count, 2)
        XCTAssertTrue(settings.permissions?.allow?.contains("Bash(git *)") ?? false)
        XCTAssertTrue(settings.permissions?.deny?.contains("Bash(rm *)") ?? false)
    }

    func testPermissionsAllowOnly() throws {
        let json = """
        {
            "permissions": {
                "allow": ["Read(*)"]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.permissions?.allow?.count, 1)
        XCTAssertNil(settings.permissions?.deny)
    }

    func testPermissionsEmptyArrays() throws {
        let json = """
        {
            "permissions": {
                "allow": [],
                "deny": []
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.permissions?.allow?.count, 0)
        XCTAssertEqual(settings.permissions?.deny?.count, 0)
    }

    // MARK: - Hooks Parsing

    func testHooksParsing() throws {
        let json = """
        {
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Bash",
                        "command": "echo 'checking'",
                        "timeout": 5000
                    },
                    {
                        "matcher": "Edit",
                        "prompt": "Review this edit carefully"
                    }
                ],
                "PostToolUse": [
                    {
                        "matcher": "Bash",
                        "command": "log-tool-use.sh"
                    }
                ],
                "Notification": [
                    {
                        "command": "notify.sh"
                    }
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.hooks?.count, 3)

        let preToolUse = settings.hooks?["PreToolUse"]
        XCTAssertEqual(preToolUse?.count, 2)
        XCTAssertEqual(preToolUse?[0].matcher, "Bash")
        XCTAssertEqual(preToolUse?[0].command, "echo 'checking'")
        XCTAssertEqual(preToolUse?[0].timeout, 5000)
        XCTAssertEqual(preToolUse?[1].matcher, "Edit")
        XCTAssertEqual(preToolUse?[1].prompt, "Review this edit carefully")

        let postToolUse = settings.hooks?["PostToolUse"]
        XCTAssertEqual(postToolUse?.count, 1)
        XCTAssertEqual(postToolUse?[0].command, "log-tool-use.sh")

        let notification = settings.hooks?["Notification"]
        XCTAssertEqual(notification?.count, 1)
    }

    func testHookHandlerType() throws {
        let commandHook = ClaudeHook(command: "echo test")
        XCTAssertEqual(commandHook.handlerType, .command)

        let promptHook = ClaudeHook(prompt: "Review this")
        XCTAssertEqual(promptHook.handlerType, .prompt)

        let agentHook = ClaudeHook(agent: "reviewer")
        XCTAssertEqual(agentHook.handlerType, .agent)

        let emptyHook = ClaudeHook()
        XCTAssertEqual(emptyHook.handlerType, .command) // default
    }

    func testHookEncodingDecodingRoundTrip() throws {
        let hook = ClaudeHook(
            matcher: "Bash",
            command: "safety-check.sh",
            timeout: 3000
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(hook)
        let decoded = try JSONDecoder().decode(ClaudeHook.self, from: data)

        XCTAssertEqual(decoded.matcher, "Bash")
        XCTAssertEqual(decoded.command, "safety-check.sh")
        XCTAssertEqual(decoded.timeout, 3000)
        XCTAssertNil(decoded.prompt)
        XCTAssertNil(decoded.agent)
    }

    // MARK: - Plugins Parsing

    func testPluginsParsing() throws {
        let json = """
        {
            "enabledPlugins": {
                "chief-of-staff@example-plugins": true,
                "travel-agent@example-plugins": true,
                "old-plugin@deprecated-marketplace": false
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: data)

        XCTAssertEqual(settings.enabledPlugins?.count, 3)
        XCTAssertEqual(settings.enabledPlugins?["chief-of-staff@example-plugins"], true)
        XCTAssertEqual(settings.enabledPlugins?["old-plugin@deprecated-marketplace"], false)
    }

    func testPluginMerge() {
        let enabledPlugins: [String: Bool] = [
            "chief@marketplace": true,
            "stale@old-mp": false,
        ]
        let installedPlugins: [String: InstalledPluginInfo] = [
            "chief@marketplace": InstalledPluginInfo(version: "1.2.0", installedAt: nil, marketplace: "marketplace"),
        ]
        let marketplaces: [String: MarketplaceInfo] = [
            "marketplace": MarketplaceInfo(path: "/path/to/marketplace", type: nil),
        ]

        let merged = ClaudeSettingsService.mergePlugins(
            enabledPlugins: enabledPlugins,
            installedPlugins: installedPlugins,
            marketplaces: marketplaces
        )

        XCTAssertEqual(merged.count, 2) // chief (installed) + stale (enabled but not installed)

        let chief = merged.first { $0.name == "chief" }
        XCTAssertNotNil(chief)
        XCTAssertEqual(chief?.marketplace, "marketplace")
        XCTAssertTrue(chief?.enabled ?? false)
        XCTAssertEqual(chief?.version, "1.2.0")

        let stale = merged.first { $0.name == "stale" }
        XCTAssertNotNil(stale)
        XCTAssertEqual(stale?.marketplace, "old-mp")
        XCTAssertFalse(stale?.enabled ?? true)
    }

    // MARK: - MCP Config Parsing

    func testMCPStdioTransport() {
        let config = MCPServerConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem"],
            env: ["HOME": "/Users/test"]
        )

        XCTAssertEqual(config.inferredTransport, .stdio)
    }

    func testMCPHttpTransport() {
        let config = MCPServerConfig(
            url: "https://travel-hub.shahine.com/mcp",
            transport: "http"
        )

        XCTAssertEqual(config.inferredTransport, .http)
    }

    func testMCPSSETransport() {
        let config = MCPServerConfig(
            url: "https://example.com/sse",
            transport: "sse"
        )

        XCTAssertEqual(config.inferredTransport, .sse)
    }

    func testMCPTransportInferredFromURL() {
        // When transport is not specified but url is present and command is nil, infer http
        let config = MCPServerConfig(url: "https://example.com/mcp")

        XCTAssertEqual(config.inferredTransport, .http)
    }

    func testMCPTransportDefaultsToStdio() {
        // When nothing is specified, default to stdio
        let config = MCPServerConfig(command: "/usr/bin/some-server")

        XCTAssertEqual(config.inferredTransport, .stdio)
    }

    func testMCPConfigFileParsing() throws {
        let json = """
        {
            "mcpServers": {
                "fastmail": {
                    "url": "https://fastmail.shahine.com/mcp",
                    "transport": "http"
                },
                "parcel": {
                    "command": "npx",
                    "args": ["-y", "parcel-mcp-server"],
                    "env": {
                        "PARCEL_API_KEY": "test-key"
                    }
                },
                "travel-hub": {
                    "url": "https://travel-hub.shahine.com/mcp",
                    "transport": "http"
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(MCPConfigFile.self, from: data)

        XCTAssertEqual(config.mcpServers.count, 3)

        let fastmail = config.mcpServers["fastmail"]
        XCTAssertNotNil(fastmail)
        XCTAssertEqual(fastmail?.url, "https://fastmail.shahine.com/mcp")
        XCTAssertEqual(fastmail?.inferredTransport, .http)

        let parcel = config.mcpServers["parcel"]
        XCTAssertNotNil(parcel)
        XCTAssertEqual(parcel?.command, "npx")
        XCTAssertEqual(parcel?.args, ["-y", "parcel-mcp-server"])
        XCTAssertEqual(parcel?.env?["PARCEL_API_KEY"], "test-key")
        XCTAssertEqual(parcel?.inferredTransport, .stdio)

        let travelHub = config.mcpServers["travel-hub"]
        XCTAssertNotNil(travelHub)
        XCTAssertEqual(travelHub?.inferredTransport, .http)
    }

    func testMCPServerConversion() {
        let configs: [String: MCPServerConfig] = [
            "my-stdio-server": MCPServerConfig(
                command: "/usr/local/bin/mcp-server",
                args: ["--port", "3000"],
                env: ["KEY": "value"]
            ),
            "my-http-server": MCPServerConfig(
                url: "https://example.com/mcp",
                transport: "http"
            ),
        ]

        let servers = ClaudeSettingsService.mcpServers(from: configs)
        XCTAssertEqual(servers.count, 2)

        let httpServer = servers.first { $0.name == "my-http-server" }
        XCTAssertNotNil(httpServer)
        XCTAssertEqual(httpServer?.transport, .http)
        XCTAssertEqual(httpServer?.url, "https://example.com/mcp")

        let stdioServer = servers.first { $0.name == "my-stdio-server" }
        XCTAssertNotNil(stdioServer)
        XCTAssertEqual(stdioServer?.transport, .stdio)
        XCTAssertEqual(stdioServer?.command, "/usr/local/bin/mcp-server")
        XCTAssertEqual(stdioServer?.args, ["--port", "3000"])
        XCTAssertEqual(stdioServer?.env["KEY"], "value")
    }

    func testMCPServerConfigsRoundTrip() {
        let servers = [
            MCPServer(
                name: "test-stdio",
                transport: .stdio,
                command: "my-server",
                args: ["--flag"],
                env: ["SECRET": "abc"]
            ),
            MCPServer(
                name: "test-http",
                transport: .http,
                url: "https://test.com/mcp"
            ),
            MCPServer(
                name: "test-sse",
                transport: .sse,
                url: "https://test.com/sse"
            ),
        ]

        let configs = ClaudeSettingsService.mcpServerConfigs(from: servers)

        XCTAssertEqual(configs.count, 3)

        let stdioConfig = configs["test-stdio"]
        XCTAssertEqual(stdioConfig?.command, "my-server")
        XCTAssertEqual(stdioConfig?.args, ["--flag"])
        XCTAssertEqual(stdioConfig?.env?["SECRET"], "abc")
        XCTAssertNil(stdioConfig?.url)

        let httpConfig = configs["test-http"]
        XCTAssertEqual(httpConfig?.url, "https://test.com/mcp")
        XCTAssertEqual(httpConfig?.transport, "http")
        XCTAssertNil(httpConfig?.command)

        let sseConfig = configs["test-sse"]
        XCTAssertEqual(sseConfig?.url, "https://test.com/sse")
        XCTAssertEqual(sseConfig?.transport, "sse")
    }

    // MARK: - Permission Category Inference

    func testPermissionCategoryInference() {
        XCTAssertEqual(PermissionCategory.infer(from: "Bash(git push)"), .git)
        XCTAssertEqual(PermissionCategory.infer(from: "Bash(gh pr create)"), .git)
        XCTAssertEqual(PermissionCategory.infer(from: "Bash(npm install)"), .buildTools)
        XCTAssertEqual(PermissionCategory.infer(from: "Bash(brew install)"), .buildTools)
        XCTAssertEqual(PermissionCategory.infer(from: "Bash(echo hello)"), .bash)
        XCTAssertEqual(PermissionCategory.infer(from: "Read(*)"), .fileAccess)
        XCTAssertEqual(PermissionCategory.infer(from: "Edit(*)"), .fileAccess)
        XCTAssertEqual(PermissionCategory.infer(from: "Write(*)"), .fileAccess)
        XCTAssertEqual(PermissionCategory.infer(from: "WebFetch(*)"), .webAccess)
        XCTAssertEqual(PermissionCategory.infer(from: "mcp__fastmail__list_emails"), .mcpTools)
        XCTAssertEqual(PermissionCategory.infer(from: "Skill(my-skill)"), .skills)
        XCTAssertEqual(PermissionCategory.infer(from: "something_unknown"), .other)
    }
}
