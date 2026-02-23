import AppKit
import UniformTypeIdentifiers

/// Describes an export file's metadata for NSSavePanel.
struct ExportFileType: Sendable {
    let defaultName: String
    let allowedContentTypes: [UTType]

    init(defaultName: String, allowedContentTypes: [UTType]) {
        self.defaultName = defaultName
        self.allowedContentTypes = allowedContentTypes
    }
}

/// A preview of what an import operation will do, shown in the confirmation sheet.
struct ImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let sectionName: String
    let isReplace: Bool
    let newItems: [String]
    let updatedItems: [String]
    let unchangedCount: Int
    let warnings: [String]

    var totalChanges: Int { newItems.count + updatedItems.count }

    var summary: String {
        if isReplace {
            return "Replace current \(sectionName) configuration"
        }
        var parts: [String] = []
        if !newItems.isEmpty { parts.append("\(newItems.count) new") }
        if !updatedItems.isEmpty { parts.append("\(updatedItems.count) updated") }
        if unchangedCount > 0 { parts.append("\(unchangedCount) unchanged") }
        return parts.joined(separator: ", ")
    }
}

/// Shared NSSavePanel / NSOpenPanel wrappers for import/export operations.
@MainActor
struct ImportExportService {

    // MARK: - Export

    /// Shows an NSSavePanel and writes the content to the chosen location.
    /// Returns `true` if the file was saved, `false` if cancelled.
    @discardableResult
    static func export(content: String, fileType: ExportFileType) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileType.defaultName
        panel.allowedContentTypes = fileType.allowedContentTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export"
        panel.message = "Choose where to save the exported file."

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return false
        }
    }

    // MARK: - Import

    /// Shows an NSOpenPanel and returns the file contents and filename.
    /// Returns `nil` if cancelled.
    static func importFile(allowedContentTypes: [UTType], title: String = "Import") -> (content: String, fileName: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = title
        panel.message = "Choose a file to import."

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return (content: content, fileName: url.lastPathComponent)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import Failed"
            alert.informativeText = "Could not read the file: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            return nil
        }
    }

    /// Shows an NSOpenPanel and returns the file URL (for cases like Brewfile where we need the path).
    static func importFileURL(allowedContentTypes: [UTType], title: String = "Import") -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = title
        panel.message = "Choose a file to import."

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Binary Export

    /// Shows an NSSavePanel and writes raw data to the chosen location.
    /// Use this for encrypted files or other binary content.
    @discardableResult
    static func exportData(_ data: Data, fileType: ExportFileType) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileType.defaultName
        panel.allowedContentTypes = fileType.allowedContentTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export"
        panel.message = "Choose where to save the exported file."

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return false
        }
    }

    // MARK: - Binary Import

    /// Shows an NSOpenPanel and returns the raw file data and filename.
    /// Use this for encrypted files or other binary content.
    static func importFileData(allowedContentTypes: [UTType], title: String = "Import") -> (data: Data, fileName: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = title
        panel.message = "Choose a file to import."

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return (data: data, fileName: url.lastPathComponent)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import Failed"
            alert.informativeText = "Could not read the file: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            return nil
        }
    }

    // MARK: - Header Generation

    /// Generates a standard shell export header comment.
    static func shellHeader(section: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date())
        return """
        #!/bin/zsh
        # ShellCraft Export — \(section)
        # \(date)

        """
    }
}
