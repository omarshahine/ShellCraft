import Foundation

@MainActor @Observable
final class PathManagerViewModel {

    // MARK: - Published State

    var entries: [PathEntry] = []
    var hasUnsavedChanges: Bool = false
    var errorMessage: String? = nil
    var isLoading: Bool = false
    var isValidating: Bool = false

    // MARK: - Internal State

    private var rawLines: [String: [String]] = [:]
    private var savedSnapshot: [PathEntry] = []

    // MARK: - Load

    func load() {
        isLoading = true
        errorMessage = nil

        do {
            let config = try ShellConfigParser.parse()
            entries = config.pathEntries
            rawLines = config.rawLines

            // Assign sequential order based on parse order
            for index in entries.indices {
                entries[index].order = index
            }

            savedSnapshot = entries
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to parse PATH configuration: \(error.localizedDescription)"
        }

        isLoading = false

        // Kick off async validation
        Task {
            await validatePaths()
        }
    }

    // MARK: - Save

    func save() {
        errorMessage = nil

        do {
            // Find the file containing PATH exports — default to ~/.zshrc
            let targetFile = entries.first?.sourceFile ?? "~/.zshrc"
            var lines = rawLines[targetFile] ?? (try? FileIOService.readLines(at: targetFile)) ?? []

            // Find existing PATH export lines and remove them
            var indicesToRemove: [Int] = []
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmed
                if trimmed.wholeMatch(of: ShellLineParser.pathExportPattern) != nil ||
                   trimmed.wholeMatch(of: ShellLineParser.pathPrependPattern) != nil {
                    indicesToRemove.append(index)
                }
            }

            // Remove in reverse order to preserve indices
            for index in indicesToRemove.reversed() {
                lines.remove(at: index)
            }

            // Generate new PATH export line from ordered entries
            if !entries.isEmpty {
                let pathLine = ShellConfigWriter.generatePathExportLine(entries: entries)

                // Insert at the position of the first removed line, or append
                if let firstRemoved = indicesToRemove.first, firstRemoved < lines.count {
                    lines.insert(pathLine, at: firstRemoved)
                } else {
                    lines.append(pathLine)
                }
            }

            try ShellConfigWriter.writeLines(lines, to: targetFile)

            // Reload for fresh state
            load()
        } catch {
            errorMessage = "Failed to save PATH: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    func add(path: String) {
        let entry = PathEntry(
            path: path,
            order: entries.count,
            sourceFile: "~/.zshrc"
        )
        entries.append(entry)
        markDirty()

        // Validate the new entry
        Task {
            await validateSingleEntry(entry.id)
        }
    }

    func remove(_ entry: PathEntry) {
        entries.removeAll { $0.id == entry.id }
        // Reassign order
        for index in entries.indices {
            entries[index].order = index
        }
        markDirty()
    }

    func move(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        // Reassign order after move
        for index in entries.indices {
            entries[index].order = index
        }
        markDirty()
    }

    // MARK: - Validation

    func validatePaths() async {
        isValidating = true
        let validated = await PathValidator.shared.validateAll(entries)
        entries = validated
        isValidating = false
    }

    private func validateSingleEntry(_ id: UUID) async {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let exists = await PathValidator.shared.validate(entries[index].path)
        entries[index].exists = exists
        entries[index].expandedPath = entries[index].path.expandingTildeInPath
    }

    // MARK: - Discard

    func discard() {
        entries = savedSnapshot
        hasUnsavedChanges = false
    }

    // MARK: - Import / Export

    func exportData() -> String {
        var output = ImportExportService.shellHeader(section: "PATH")
        if !entries.isEmpty {
            output += ShellConfigWriter.generatePathExportLine(entries: entries) + "\n"
        }
        return output
    }

    func previewImport(_ content: String) -> ImportPreview {
        let imported = parsePathEntries(from: content)
        let existingPaths = Set(entries.map(\.path))
        var newItems: [String] = []
        var unchanged = 0

        for path in imported {
            if existingPaths.contains(path) {
                unchanged += 1
            } else {
                newItems.append(path)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "PATH",
            isReplace: false,
            newItems: newItems,
            updatedItems: [],
            unchangedCount: unchanged,
            warnings: []
        )
    }

    func applyImport(_ content: String) {
        let imported = parsePathEntries(from: content)
        let existingPaths = Set(entries.map(\.path))

        for path in imported where !existingPaths.contains(path) {
            let entry = PathEntry(
                path: path,
                order: entries.count,
                sourceFile: "~/.zshrc"
            )
            entries.append(entry)
        }

        markDirty()

        Task {
            await validatePaths()
        }
    }

    private func parsePathEntries(from content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var paths: [String] = []

        for line in lines {
            let trimmed = line.trimmed
            // Match export PATH=...
            if let match = trimmed.wholeMatch(of: ShellLineParser.pathExportPattern) {
                let value = ShellLineParser.unquote(String(match.1))
                for component in value.components(separatedBy: ":") {
                    var cleaned = ShellLineParser.unquote(component.trimmed)
                    cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                    if cleaned.isEmpty || cleaned == "$PATH" || cleaned == "${PATH}" { continue }
                    paths.append(cleaned)
                }
            }
            // Match PATH="newpath:$PATH"
            if let match = trimmed.wholeMatch(of: ShellLineParser.pathPrependPattern) {
                paths.append(String(match.1))
            }
        }

        return paths
    }

    // MARK: - Private

    private func markDirty() {
        hasUnsavedChanges = true
    }
}
