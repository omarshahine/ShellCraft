import Foundation

// MARK: - Hook Action

/// A single hook action within a hook rule.
/// Maps to: `{"type": "command", "command": "...", "timeout": 600, "async": true}`
struct ClaudeHookAction: Codable, Hashable {
    var type: String?
    var command: String?
    var prompt: String?
    var agent: String?
    var timeout: Int?
    var statusMessage: String?
    var isAsync: Bool?

    enum CodingKeys: String, CodingKey {
        case type, command, prompt, agent, timeout, statusMessage
        case isAsync = "async"
    }

    init(
        type: String? = nil,
        command: String? = nil,
        prompt: String? = nil,
        agent: String? = nil,
        timeout: Int? = nil,
        statusMessage: String? = nil,
        isAsync: Bool? = nil
    ) {
        self.type = type
        self.command = command
        self.prompt = prompt
        self.agent = agent
        self.timeout = timeout
        self.statusMessage = statusMessage
        self.isAsync = isAsync
    }
}

// MARK: - Hook Rule

/// A hook rule: matches a tool pattern and defines one or more hook actions.
/// Maps to: `{"matcher": "Bash", "hooks": [...]}`
struct ClaudeHook: Identifiable, Hashable, Codable {
    var id: UUID
    var matcher: String?
    var actions: [ClaudeHookAction]

    // MARK: - Convenience Accessors (primary action)

    /// The command of the primary (first) action.
    var command: String? {
        get { actions.first?.command }
        set {
            ensureFirstAction()
            actions[0].command = newValue
            actions[0].type = "command"
        }
    }

    /// The prompt of the primary (first) action.
    var prompt: String? {
        get { actions.first?.prompt }
        set {
            ensureFirstAction()
            actions[0].prompt = newValue
            actions[0].type = "prompt"
        }
    }

    /// The agent of the primary (first) action.
    var agent: String? {
        get { actions.first?.agent }
        set {
            ensureFirstAction()
            actions[0].agent = newValue
            actions[0].type = "agent"
        }
    }

    /// The timeout of the primary (first) action.
    var timeout: Int? {
        get { actions.first?.timeout }
        set {
            ensureFirstAction()
            actions[0].timeout = newValue
        }
    }

    private mutating func ensureFirstAction() {
        if actions.isEmpty {
            actions.append(ClaudeHookAction())
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        matcher: String? = nil,
        command: String? = nil,
        prompt: String? = nil,
        agent: String? = nil,
        timeout: Int? = nil
    ) {
        self.id = id
        self.matcher = matcher

        var action = ClaudeHookAction()
        if let command {
            action.type = "command"
            action.command = command
        } else if let prompt {
            action.type = "prompt"
            action.prompt = prompt
        } else if let agent {
            action.type = "agent"
            action.agent = agent
        }
        action.timeout = timeout
        self.actions = (command != nil || prompt != nil || agent != nil) ? [action] : []
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case matcher, hooks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.matcher = try container.decodeIfPresent(String.self, forKey: .matcher)
        self.actions = try container.decodeIfPresent([ClaudeHookAction].self, forKey: .hooks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(matcher, forKey: .matcher)
        if !actions.isEmpty {
            try container.encode(actions, forKey: .hooks)
        }
    }

    // MARK: - Hashable (by stored properties only)

    static func == (lhs: ClaudeHook, rhs: ClaudeHook) -> Bool {
        lhs.id == rhs.id && lhs.matcher == rhs.matcher && lhs.actions == rhs.actions
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(matcher)
        hasher.combine(actions)
    }

    // MARK: - Handler Type

    var handlerType: HandlerType {
        guard let type = actions.first?.type else {
            return .command
        }
        switch type {
        case "prompt": return .prompt
        case "agent": return .agent
        default: return .command
        }
    }

    enum HandlerType: String, CaseIterable {
        case command = "Command"
        case prompt = "Prompt"
        case agent = "Agent"
    }
}

// MARK: - Hook Event Types

enum HookEventType: String, CaseIterable, Identifiable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
    case permissionRequest = "PermissionRequest"

    var id: String { rawValue }
}
