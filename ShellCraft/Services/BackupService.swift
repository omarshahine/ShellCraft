import Foundation

struct BackupService {
    static let backupRoot = NSHomeDirectory() + "/.config/shellcraft/backups"

    /// Creates a timestamped backup of a file
    static func backup(file path: String) throws {
        let expandedPath = path.expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else { return }

        let filename = URL(fileURLWithPath: expandedPath).lastPathComponent
        let backupDir = "\(backupRoot)/\(filename)"

        // Create backup directory if needed
        try FileManager.default.createDirectory(
            atPath: backupDir,
            withIntermediateDirectories: true
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let backupPath = "\(backupDir)/\(filename).\(timestamp)"
        try FileManager.default.copyItem(atPath: expandedPath, toPath: backupPath)

        // Clean up old backups (keep last 20)
        try pruneBackups(in: backupDir, keep: 20)
    }

    /// Lists backups for a given file
    static func listBackups(for filename: String) throws -> [BackupInfo] {
        let backupDir = "\(backupRoot)/\(filename)"
        guard FileManager.default.fileExists(atPath: backupDir) else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(atPath: backupDir)
        return contents.compactMap { name in
            let path = "\(backupDir)/\(name)"
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let date = attributes?[.modificationDate] as? Date ?? Date()
            let size = attributes?[.size] as? Int ?? 0
            return BackupInfo(path: path, filename: name, date: date, size: size)
        }
        .sorted { $0.date > $1.date }
    }

    /// Restores a backup to the original location using an atomic rename pattern.
    /// The original file is moved aside before the backup is copied in, with rollback
    /// on failure to prevent data loss.
    static func restore(backup: BackupInfo, to originalPath: String) throws {
        let expandedPath = originalPath.expandingTildeInPath
        // Backup the current version before restoring
        try self.backup(file: originalPath)

        // Atomic restore: rename aside → copy backup → clean up
        let asidePath = expandedPath + ".shellcraft-aside"
        try FileManager.default.moveItem(atPath: expandedPath, toPath: asidePath)
        do {
            try FileManager.default.copyItem(atPath: backup.path, toPath: expandedPath)
            // Copy succeeded — remove the aside file
            try? FileManager.default.removeItem(atPath: asidePath)
        } catch {
            // Rollback: move the original back
            try? FileManager.default.moveItem(atPath: asidePath, toPath: expandedPath)
            throw error
        }
    }

    private static func pruneBackups(in directory: String, keep: Int) throws {
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory)
        let sorted = contents.sorted()
        if sorted.count > keep {
            for filename in sorted.prefix(sorted.count - keep) {
                try FileManager.default.removeItem(atPath: "\(directory)/\(filename)")
            }
        }
    }
}

struct BackupInfo: Identifiable {
    let id = UUID()
    let path: String
    let filename: String
    let date: Date
    let size: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
