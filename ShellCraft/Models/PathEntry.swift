import Foundation

struct PathEntry: Identifiable, Hashable {
    let id: UUID
    var path: String
    var expandedPath: String
    var exists: Bool
    var order: Int
    var sourceFile: String

    init(
        id: UUID = UUID(),
        path: String,
        expandedPath: String = "",
        exists: Bool = true,
        order: Int = 0,
        sourceFile: String = "~/.zshrc"
    ) {
        self.id = id
        self.path = path
        self.expandedPath = expandedPath.isEmpty ? path.expandingTildeInPath : expandedPath
        self.exists = exists
        self.order = order
        self.sourceFile = sourceFile
    }
}
