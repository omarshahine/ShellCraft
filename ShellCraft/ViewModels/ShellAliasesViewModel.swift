import Foundation

@MainActor @Observable
final class ShellAliasesViewModel {

    // MARK: - Published State

    var aliases: [ShellAlias] = []
    var searchText: String = ""
    var selectedCategory: AliasCategory? = nil
    var hasUnsavedChanges: Bool = false
    var errorMessage: String? = nil
    var isLoading: Bool = false

    // MARK: - Internal State

    /// Raw lines keyed by source file, used for round-trip fidelity
    private var rawLines: [String: [String]] = [:]
    /// Snapshot of aliases at last save/load, for dirty tracking
    private var savedSnapshot: [ShellAlias] = []

    // MARK: - Computed

    var filteredAliases: [ShellAlias] {
        aliases.filter { alias in
            let matchesSearch = searchText.isEmpty ||
                alias.name.localizedCaseInsensitiveContains(searchText) ||
                alias.expansion.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || alias.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    var categories: [AliasCategory] {
        AliasCategory.allCases
    }

    // MARK: - Load

    func load() {
        isLoading = true
        errorMessage = nil

        do {
            let config = try ShellConfigParser.parse()
            aliases = config.aliases
            rawLines = config.rawLines
            savedSnapshot = aliases
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to parse shell config: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Save

    func save() {
        errorMessage = nil

        do {
            // Group aliases by source file for targeted writes
            let aliasesByFile = Dictionary(grouping: aliases, by: \.sourceFile)

            for (file, fileAliases) in aliasesByFile {
                guard var lines = rawLines[file] else { continue }

                // Build modifications in reverse line-number order to preserve indices
                var modifications: [ShellConfigWriter.Modification] = []

                // Find aliases that were updated (exist in saved snapshot with same source/line)
                for alias in fileAliases {
                    if let original = savedSnapshot.first(where: { $0.id == alias.id }) {
                        // Existing alias — update in place
                        let lineIndex = original.lineNumber - 1
                        let newLine = ShellConfigWriter.generateAliasLine(
                            name: alias.name,
                            expansion: alias.expansion,
                            enabled: alias.isEnabled
                        )
                        modifications.append(.updateLine(lineIndex, newLine))
                    }
                }

                // Find aliases that were deleted
                let currentIDs = Set(aliases.map(\.id))
                let deletedAliases = savedSnapshot.filter { saved in
                    saved.sourceFile == file && !currentIDs.contains(saved.id)
                }.sorted(by: { $0.lineNumber > $1.lineNumber }) // reverse order for safe deletion

                for deleted in deletedAliases {
                    modifications.append(.deleteLine(deleted.lineNumber - 1))
                }

                // Find new aliases (not in saved snapshot)
                let savedIDs = Set(savedSnapshot.map(\.id))
                let newAliases = fileAliases.filter { !savedIDs.contains($0.id) }
                for newAlias in newAliases {
                    let line = ShellConfigWriter.generateAliasLine(
                        name: newAlias.name,
                        expansion: newAlias.expansion,
                        enabled: newAlias.isEnabled
                    )
                    modifications.append(.appendLine(line))
                }

                lines = ShellConfigWriter.apply(modifications: modifications, to: lines)
                try ShellConfigWriter.writeLines(lines, to: file)
            }

            // Handle new aliases targeting the default file
            let savedIDs = Set(savedSnapshot.map(\.id))
            let newDefaultAliases = aliases.filter {
                !savedIDs.contains($0.id) && aliasesByFile[$0.sourceFile] == nil
            }
            if !newDefaultAliases.isEmpty {
                let defaultFile = "~/.zshrc"
                var lines = rawLines[defaultFile] ?? (try? FileIOService.readLines(at: defaultFile)) ?? []
                for alias in newDefaultAliases {
                    lines.append(ShellConfigWriter.generateAliasLine(
                        name: alias.name,
                        expansion: alias.expansion,
                        enabled: alias.isEnabled
                    ))
                }
                try ShellConfigWriter.writeLines(lines, to: defaultFile)
            }

            // Reload to get fresh line numbers
            load()
        } catch {
            errorMessage = "Failed to save aliases: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    func add(name: String, expansion: String) {
        let category = AliasCategory.infer(from: name, expansion: expansion)
        let alias = ShellAlias(
            name: name,
            expansion: expansion,
            sourceFile: "~/.zshrc",
            lineNumber: 0, // will be assigned on save
            category: category,
            isEnabled: true
        )
        aliases.append(alias)
        markDirty()
    }

    func update(_ alias: ShellAlias) {
        guard let index = aliases.firstIndex(where: { $0.id == alias.id }) else { return }
        aliases[index] = alias
        markDirty()
    }

    func delete(_ alias: ShellAlias) {
        aliases.removeAll { $0.id == alias.id }
        markDirty()
    }

    func toggleEnabled(_ alias: ShellAlias) {
        guard let index = aliases.firstIndex(where: { $0.id == alias.id }) else { return }
        aliases[index].isEnabled.toggle()
        markDirty()
    }

    // MARK: - Discard

    func discard() {
        aliases = savedSnapshot
        hasUnsavedChanges = false
    }

    // MARK: - Import / Export

    /// Generates a sourceable shell script with all aliases.
    func exportData() -> String {
        var output = ImportExportService.shellHeader(section: "Aliases")
        for alias in aliases {
            output += ShellConfigWriter.generateAliasLine(
                name: alias.name,
                expansion: alias.expansion,
                enabled: alias.isEnabled
            ) + "\n"
        }
        return output
    }

    /// Parses an imported shell file and returns a preview of what would change.
    func previewImport(_ content: String) -> ImportPreview {
        let lines = content.components(separatedBy: "\n")
        var newItems: [String] = []
        var updatedItems: [String] = []
        var unchanged = 0

        for line in lines {
            guard let parsed = ShellLineParser.parseAlias(from: line) else { continue }
            if let existing = aliases.first(where: { $0.name == parsed.name }) {
                if existing.expansion != parsed.expansion || existing.isEnabled != parsed.enabled {
                    updatedItems.append(parsed.name)
                } else {
                    unchanged += 1
                }
            } else {
                newItems.append(parsed.name)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "Aliases",
            isReplace: false,
            newItems: newItems,
            updatedItems: updatedItems,
            unchangedCount: unchanged,
            warnings: []
        )
    }

    /// Applies an imported shell file, merging aliases by name.
    func applyImport(_ content: String) {
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            guard let parsed = ShellLineParser.parseAlias(from: line) else { continue }
            let category = AliasCategory.infer(from: parsed.name, expansion: parsed.expansion)

            if let index = aliases.firstIndex(where: { $0.name == parsed.name }) {
                aliases[index].expansion = parsed.expansion
                aliases[index].isEnabled = parsed.enabled
                aliases[index].category = category
            } else {
                let alias = ShellAlias(
                    name: parsed.name,
                    expansion: parsed.expansion,
                    sourceFile: "~/.zshrc",
                    lineNumber: 0,
                    category: category,
                    isEnabled: parsed.enabled
                )
                aliases.append(alias)
            }
        }

        markDirty()
    }

    // MARK: - Private

    private func markDirty() {
        hasUnsavedChanges = true
    }
}
