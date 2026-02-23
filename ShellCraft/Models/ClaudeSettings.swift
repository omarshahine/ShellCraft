import Foundation

// MARK: - StatusLine (handles both string and object formats)

/// Claude Code's statusLine can be either a plain string or
/// an object like `{"type": "command", "command": "bash ..."}`.
enum StatusLineValue: Codable, Equatable {
    case text(String)
    case config(StatusLineConfig)

    struct StatusLineConfig: Codable, Equatable {
        var type: String?
        var command: String?
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            self = .text(stringValue)
            return
        }
        let config = try StatusLineConfig(from: decoder)
        self = .config(config)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .config(let config):
            try config.encode(to: encoder)
        }
    }

    /// Display text for the UI (the command string or plain text).
    var displayText: String {
        switch self {
        case .text(let string): string
        case .config(let config): config.command ?? ""
        }
    }
}

// MARK: - Attribution (handles both legacy string and object formats)

/// Claude Code's attribution can be either a legacy plain string
/// or an object like `{"commit": "Co-Authored-By: ...", "pr": "..."}`.
enum AttributionValue: Codable, Equatable {
    case text(String)
    case config(AttributionConfig)

    struct AttributionConfig: Codable, Equatable {
        var commit: String?
        var pr: String?
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            self = .text(stringValue)
            return
        }
        let config = try AttributionConfig(from: decoder)
        self = .config(config)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .config(let config):
            try config.encode(to: encoder)
        }
    }

    /// The commit attribution text (from either format).
    var commitText: String {
        switch self {
        case .text(let string): string
        case .config(let config): config.commit ?? ""
        }
    }

    /// The PR attribution text (only available in config format).
    var prText: String {
        switch self {
        case .text: ""
        case .config(let config): config.pr ?? ""
        }
    }
}

// MARK: - Settings

struct ClaudeSettings: Codable {
    var model: String?
    var outputStyle: String?
    var statusLine: StatusLineValue?
    var attribution: AttributionValue?
    var permissions: ClaudePermissions?
    var hooks: [String: [ClaudeHook]]?
    var enabledPlugins: [String: Bool]?
    var env: [String: String]?
    var skipDangerousModePermissionPrompt: Bool?
    var alwaysThinkingEnabled: Bool?
    var cleanupPeriodDays: Int?
    var language: String?
    var autoUpdatesChannel: String?
    var showTurnDuration: Bool?
    var terminalProgressBarEnabled: Bool?
    var prefersReducedMotion: Bool?
    var teammateMode: String?
    var respectGitignore: Bool?
    var plansDirectory: String?
    var disableAllHooks: Bool?
    var spinnerTipsEnabled: Bool?

    init() {}

    enum CodingKeys: String, CodingKey, CaseIterable {
        case model, outputStyle, statusLine, attribution
        case permissions, hooks, enabledPlugins, env
        case skipDangerousModePermissionPrompt
        case alwaysThinkingEnabled, cleanupPeriodDays, language
        case autoUpdatesChannel, showTurnDuration, terminalProgressBarEnabled
        case prefersReducedMotion, teammateMode, respectGitignore
        case plansDirectory, disableAllHooks, spinnerTipsEnabled
    }

    /// All JSON key strings managed by this model (used for round-trip merge).
    static var allCodingKeyStrings: Set<String> {
        Set(CodingKeys.allCases.map(\.stringValue))
    }
}

// MARK: - Permissions

struct ClaudePermissions: Codable {
    var allow: [String]?
    var deny: [String]?
    var ask: [String]?
    var defaultMode: String?
    var additionalDirectories: [String]?
    var disableBypassPermissionsMode: String?

    init(
        allow: [String]? = nil,
        deny: [String]? = nil,
        ask: [String]? = nil,
        defaultMode: String? = nil,
        additionalDirectories: [String]? = nil,
        disableBypassPermissionsMode: String? = nil
    ) {
        self.allow = allow
        self.deny = deny
        self.ask = ask
        self.defaultMode = defaultMode
        self.additionalDirectories = additionalDirectories
        self.disableBypassPermissionsMode = disableBypassPermissionsMode
    }
}
