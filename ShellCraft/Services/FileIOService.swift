import Foundation

struct FileIOService {
    /// Reads a file and returns its contents as a string
    static func readFile(at path: String) throws -> String {
        let expandedPath = path.expandingTildeInPath
        return try String(contentsOfFile: expandedPath, encoding: .utf8)
    }

    /// Reads a file and returns its lines
    static func readLines(at path: String) throws -> [String] {
        let content = try readFile(at: path)
        return content.components(separatedBy: "\n")
    }

    /// Atomically writes content to a file (write to temp, then rename)
    static func writeFile(at path: String, content: String, backup: Bool = true) throws {
        // Resolve symlinks so atomic writes target the real file, not the symlink
        let expandedPath = URL(fileURLWithPath: path.expandingTildeInPath)
            .resolvingSymlinksInPath().path
        let url = URL(fileURLWithPath: expandedPath)

        // Create backup before writing
        if backup && FileManager.default.fileExists(atPath: expandedPath) {
            try BackupService.backup(file: expandedPath)
        }

        // Atomic write: write to temp file, then rename
        let tempPath = expandedPath + ".tmp.\(UUID().uuidString)"
        let tempURL = URL(fileURLWithPath: tempPath)

        try content.write(to: tempURL, atomically: false, encoding: .utf8)

        // Preserve original permissions if file exists
        if FileManager.default.fileExists(atPath: expandedPath) {
            let attributes = try FileManager.default.attributesOfItem(atPath: expandedPath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                try FileManager.default.setAttributes(
                    [.posixPermissions: permissions],
                    ofItemAtPath: tempPath
                )
            }
        }

        // Atomic rename
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    /// Checks if a file exists
    static func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path.expandingTildeInPath)
    }

    /// Returns the modification date of a file
    static func modificationDate(of path: String) -> Date? {
        let expandedPath = path.expandingTildeInPath
        let attributes = try? FileManager.default.attributesOfItem(atPath: expandedPath)
        return attributes?[.modificationDate] as? Date
    }
}
