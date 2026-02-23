import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case aliases
    case functions
    case ohMyZsh
    case path
    case envVars
    case secrets
    case sshConfig
    case gitConfig
    case claudeSettings
    case customTools
    case homebrew

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aliases: "Aliases"
        case .functions: "Functions"
        case .ohMyZsh: "Oh My Zsh"
        case .path: "PATH"
        case .envVars: "Environment"
        case .secrets: "Secrets"
        case .sshConfig: "SSH"
        case .gitConfig: "Git"
        case .claudeSettings: "Claude Code"
        case .customTools: "Custom Tools"
        case .homebrew: "Homebrew"
        }
    }

    var icon: String {
        switch self {
        case .aliases: "text.word.spacing"
        case .functions: "function"
        case .ohMyZsh: "terminal"
        case .path: "point.topleft.down.to.point.bottomright.curvepath"
        case .envVars: "list.bullet.rectangle"
        case .secrets: "key.fill"
        case .sshConfig: "lock.shield"
        case .gitConfig: "arrow.triangle.branch"
        case .claudeSettings: "brain"
        case .customTools: "wrench.and.screwdriver"
        case .homebrew: "mug"
        }
    }

    var group: SidebarGroup {
        switch self {
        case .aliases, .functions, .ohMyZsh, .path, .envVars: .shell
        case .secrets, .sshConfig: .security
        case .gitConfig, .claudeSettings: .developer
        case .customTools, .homebrew: .tools
        }
    }
}

enum SidebarGroup: String, CaseIterable, Identifiable {
    case shell = "Shell"
    case security = "Security"
    case developer = "Developer"
    case tools = "Tools"

    var id: String { rawValue }

    var sections: [SidebarSection] {
        SidebarSection.allCases.filter { $0.group == self }
    }
}
