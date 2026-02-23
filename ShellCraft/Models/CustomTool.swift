import Foundation

// MARK: - Tool Source

enum ToolSource: String, Hashable {
    case homebrew = "Homebrew"
    case system = "System"
    case userInstalled = "User"
    case unknown = "Unknown"

    /// Determine source from a resolved file path.
    static func from(path: String) -> ToolSource {
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Cellar/") || path.hasPrefix("/usr/local/opt/") {
            return .homebrew
        }
        if path.hasPrefix("/usr/bin/") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/") || path.hasPrefix("/usr/sbin/") {
            return .system
        }
        if path.isEmpty {
            return .unknown
        }
        return .userInstalled
    }
}

// MARK: - Custom Tool

struct CustomTool: Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var description: String
    var isInPATH: Bool
    var source: ToolSource
    var brewName: String?
    var isUserAdded: Bool

    init(
        id: UUID = UUID(),
        name: String,
        path: String = "",
        description: String = "",
        isInPATH: Bool = false,
        source: ToolSource = .unknown,
        brewName: String? = nil,
        isUserAdded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.description = description
        self.isInPATH = isInPATH
        self.source = source
        self.brewName = brewName
        self.isUserAdded = isUserAdded
    }
}
