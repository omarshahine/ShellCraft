import Foundation

actor PathValidator {
    static let shared = PathValidator()

    /// Expands shell variables ($HOME, ${HOME}) and ~ in a path.
    private func expandPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "${HOME}", with: NSHomeDirectory())
            .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
            .expandingTildeInPath
    }

    func validate(_ path: String) -> Bool {
        let expanded = expandPath(path)
        return FileManager.default.fileExists(atPath: expanded)
    }

    func validateAll(_ entries: [PathEntry]) -> [PathEntry] {
        entries.map { entry in
            var updated = entry
            let expanded = expandPath(entry.path)
            updated.expandedPath = expanded
            updated.exists = FileManager.default.fileExists(atPath: expanded)
            return updated
        }
    }
}
