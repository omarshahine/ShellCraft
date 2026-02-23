import Foundation

struct ClaudePermission: Identifiable, Hashable {
    let id: UUID
    var pattern: String
    var list: PermissionList
    var category: PermissionCategory

    init(
        id: UUID = UUID(),
        pattern: String,
        list: PermissionList,
        category: PermissionCategory = .other
    ) {
        self.id = id
        self.pattern = pattern
        self.list = list
        self.category = category.isOther ? PermissionCategory.infer(from: pattern) : category
    }

    enum PermissionList: String, CaseIterable, Identifiable {
        case allow
        case deny

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .allow: "Allow"
            case .deny: "Deny"
            }
        }
    }
}

enum PermissionCategory: String, CaseIterable, Identifiable {
    case bash = "Bash"
    case git = "Git"
    case buildTools = "Build Tools"
    case fileAccess = "File Access"
    case webAccess = "Web Access"
    case mcpTools = "MCP Tools"
    case skills = "Skills"
    case other = "Other"

    var id: String { rawValue }

    var isOther: Bool { self == .other }

    static func infer(from pattern: String) -> PermissionCategory {
        let lower = pattern.lowercased()
        if lower.hasPrefix("bash(git ") || lower.hasPrefix("bash(gh ") {
            return .git
        } else if lower.hasPrefix("bash(npm ") || lower.hasPrefix("bash(npx ") ||
                  lower.hasPrefix("bash(bun ") || lower.hasPrefix("bash(brew ") ||
                  lower.hasPrefix("bash(cargo ") || lower.hasPrefix("bash(pip ") {
            return .buildTools
        } else if lower.hasPrefix("bash(") {
            return .bash
        } else if lower.hasPrefix("read(") || lower.hasPrefix("edit(") || lower.hasPrefix("write(") {
            return .fileAccess
        } else if lower.hasPrefix("webfetch(") || lower.hasPrefix("websearch") {
            return .webAccess
        } else if lower.hasPrefix("mcp__") {
            return .mcpTools
        } else if lower.hasPrefix("skill(") {
            return .skills
        }
        return .other
    }
}
