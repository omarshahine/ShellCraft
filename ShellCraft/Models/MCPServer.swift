import Foundation

struct MCPServer: Identifiable, Hashable {
    let id: UUID
    var name: String
    var transport: Transport
    var url: String
    var command: String
    var args: [String]
    var env: [String: String]
    var source: Source

    init(
        id: UUID = UUID(),
        name: String,
        transport: Transport = .stdio,
        url: String = "",
        command: String = "",
        args: [String] = [],
        env: [String: String] = [:],
        source: Source = .mcpJson
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.url = url
        self.command = command
        self.args = args
        self.env = env
        self.source = source
    }

    /// Where the server config was loaded from.
    enum Source: String, Hashable {
        case mcpJson     // ~/.mcp.json
        case claudeJson  // ~/.claude.json
    }

    enum Transport: String, CaseIterable, Identifiable {
        case stdio
        case http
        case sse

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .stdio: "Stdio"
            case .http: "HTTP"
            case .sse: "SSE"
            }
        }

        var badgeColor: String {
            switch self {
            case .stdio: "blue"
            case .http: "green"
            case .sse: "orange"
            }
        }
    }
}
