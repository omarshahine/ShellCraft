import Foundation

struct ShellAlias: Identifiable, Hashable {
    let id: UUID
    var name: String
    var expansion: String
    var sourceFile: String
    var lineNumber: Int
    var category: AliasCategory
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        expansion: String,
        sourceFile: String,
        lineNumber: Int,
        category: AliasCategory = .general,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.expansion = expansion
        self.sourceFile = sourceFile
        self.lineNumber = lineNumber
        self.category = category
        self.isEnabled = isEnabled
    }
}

enum AliasCategory: String, CaseIterable, Identifiable {
    case git = "Git"
    case navigation = "Navigation"
    case docker = "Docker"
    case system = "System"
    case network = "Network"
    case general = "General"

    var id: String { rawValue }

    static func infer(from name: String, expansion: String) -> AliasCategory {
        let combined = (name + " " + expansion).lowercased()
        if combined.contains("git") || combined.contains("gco") || combined.contains("gst") {
            return .git
        } else if combined.contains("cd ") || combined.contains("ls") || combined.contains("..") {
            return .navigation
        } else if combined.contains("docker") || combined.contains("dps") || combined.contains("dex") {
            return .docker
        } else if combined.contains("brew") || combined.contains("sudo") || combined.contains("kill") {
            return .system
        } else if combined.contains("curl") || combined.contains("ssh") || combined.contains("ping") {
            return .network
        }
        return .general
    }
}
