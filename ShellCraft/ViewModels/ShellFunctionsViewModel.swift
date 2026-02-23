import Foundation

@MainActor @Observable
final class ShellFunctionsViewModel {

    // MARK: - Published State

    var functions: [ShellFunction] = []
    var searchText: String = ""
    var selectedFunction: ShellFunction? = nil
    var hasUnsavedChanges: Bool = false
    var errorMessage: String? = nil
    var isLoading: Bool = false

    // MARK: - Internal State

    private var rawLines: [String: [String]] = [:]
    private var savedSnapshot: [ShellFunction] = []

    // MARK: - Computed

    var filteredFunctions: [ShellFunction] {
        guard !searchText.isEmpty else { return functions }
        return functions.filter { fn in
            fn.name.localizedCaseInsensitiveContains(searchText) ||
            fn.description.localizedCaseInsensitiveContains(searchText) ||
            fn.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        errorMessage = nil

        do {
            let config = try ShellConfigParser.parse()
            functions = config.functions
            rawLines = config.rawLines
            savedSnapshot = functions
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
            // Group functions by source file
            let functionsByFile = Dictionary(grouping: functions, by: \.sourceFile)

            for (file, fileFunctions) in functionsByFile {
                guard var lines = rawLines[file] else { continue }

                // Process deletions first (from saved snapshot), in reverse line order
                let currentIDs = Set(functions.map(\.id))
                let deletedFunctions = savedSnapshot.filter { saved in
                    saved.sourceFile == file && !currentIDs.contains(saved.id)
                }.sorted(by: { $0.lineRange.lowerBound > $1.lineRange.lowerBound })

                for deleted in deletedFunctions {
                    let startIndex = deleted.lineRange.lowerBound - 1
                    let endIndex = deleted.lineRange.upperBound - 1
                    if startIndex >= 0 && endIndex < lines.count {
                        lines.removeSubrange(startIndex...endIndex)
                    }
                }

                // Process updates for existing functions
                // After deletions, line numbers may have shifted, so re-parse
                // to get accurate positions. Instead, we rebuild from scratch
                // by working with the IDs.
                let savedIDs = Set(savedSnapshot.map(\.id))
                let updatedFunctions = fileFunctions.filter { savedIDs.contains($0.id) }
                for function in updatedFunctions.sorted(by: { $0.lineRange.lowerBound > $1.lineRange.lowerBound }) {
                    if let original = savedSnapshot.first(where: { $0.id == function.id }) {
                        let startIndex = original.lineRange.lowerBound - 1
                        let endIndex = original.lineRange.upperBound - 1
                        guard startIndex >= 0 && endIndex < lines.count else { continue }

                        let newBlock = ShellConfigWriter.generateFunctionBlock(
                            name: function.name,
                            body: function.body
                        )
                        let newLines = newBlock.components(separatedBy: "\n")

                        // Prepend description comment if present
                        if !function.description.isEmpty {
                            // Check if there's already a comment before the function
                            if startIndex > 0 && lines[startIndex - 1].trimmed.hasPrefix("#") {
                                lines[startIndex - 1] = "# \(function.description)"
                            }
                        }

                        lines.replaceSubrange(startIndex...endIndex, with: newLines)
                    }
                }

                // Append new functions
                let newFunctions = fileFunctions.filter { !savedIDs.contains($0.id) }
                for function in newFunctions {
                    ShellConfigWriter.appendFunction(
                        name: function.name,
                        body: function.body,
                        description: function.description,
                        to: &lines
                    )
                }

                try ShellConfigWriter.writeLines(lines, to: file)
            }

            // Handle new functions targeting default file
            let savedIDs = Set(savedSnapshot.map(\.id))
            let newDefaultFunctions = functions.filter {
                !savedIDs.contains($0.id) && functionsByFile[$0.sourceFile] == nil
            }
            if !newDefaultFunctions.isEmpty {
                let defaultFile = "~/.zshrc"
                var lines = rawLines[defaultFile] ?? (try? FileIOService.readLines(at: defaultFile)) ?? []
                for function in newDefaultFunctions {
                    ShellConfigWriter.appendFunction(
                        name: function.name,
                        body: function.body,
                        description: function.description,
                        to: &lines
                    )
                }
                try ShellConfigWriter.writeLines(lines, to: defaultFile)
            }

            // Reload for fresh line numbers
            load()
        } catch {
            errorMessage = "Failed to save functions: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    func add(name: String, body: String, description: String = "") {
        let function = ShellFunction(
            name: name,
            body: body,
            sourceFile: "~/.zshrc",
            lineRange: 0...0, // will be assigned on save
            description: description
        )
        functions.append(function)
        markDirty()
    }

    func update(_ function: ShellFunction) {
        guard let index = functions.firstIndex(where: { $0.id == function.id }) else { return }
        functions[index] = function
        markDirty()
    }

    func delete(_ function: ShellFunction) {
        functions.removeAll { $0.id == function.id }
        if selectedFunction?.id == function.id {
            selectedFunction = nil
        }
        markDirty()
    }

    // MARK: - Discard

    func discard() {
        functions = savedSnapshot
        selectedFunction = nil
        hasUnsavedChanges = false
    }

    // MARK: - Import / Export

    func exportData() -> String {
        var output = ImportExportService.shellHeader(section: "Functions")
        for function in functions {
            if !function.description.isEmpty {
                output += "# \(function.description)\n"
            }
            output += ShellConfigWriter.generateFunctionBlock(name: function.name, body: function.body)
            output += "\n\n"
        }
        return output
    }

    func previewImport(_ content: String) -> ImportPreview {
        let parsed = parseFunctionsFromContent(content)
        var newItems: [String] = []
        var updatedItems: [String] = []
        var unchanged = 0

        for (name, body, _) in parsed {
            if let existing = functions.first(where: { $0.name == name }) {
                if existing.body != body {
                    updatedItems.append(name)
                } else {
                    unchanged += 1
                }
            } else {
                newItems.append(name)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "Functions",
            isReplace: false,
            newItems: newItems,
            updatedItems: updatedItems,
            unchangedCount: unchanged,
            warnings: []
        )
    }

    func applyImport(_ content: String) {
        let parsed = parseFunctionsFromContent(content)

        for (name, body, description) in parsed {
            if let index = functions.firstIndex(where: { $0.name == name }) {
                functions[index].body = body
                if !description.isEmpty {
                    functions[index].description = description
                }
            } else {
                let function = ShellFunction(
                    name: name,
                    body: body,
                    sourceFile: "~/.zshrc",
                    lineRange: 0...0,
                    description: description
                )
                functions.append(function)
            }
        }

        markDirty()
    }

    /// Parses function blocks from imported content.
    private func parseFunctionsFromContent(_ content: String) -> [(name: String, body: String, description: String)] {
        let lines = content.components(separatedBy: "\n")
        var results: [(String, String, String)] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if let name = ShellLineParser.parseFunctionStart(from: line) {
                // Look for a description comment on the line before
                var description = ""
                if index > 0 {
                    let prev = lines[index - 1].trimmed
                    if prev.hasPrefix("#") {
                        description = String(prev.dropFirst()).trimmed
                    }
                }

                // Collect body lines until closing brace
                var braceDepth = line.filter({ $0 == "{" }).count - line.filter({ $0 == "}" }).count
                var bodyLines: [String] = []

                if braceDepth == 0 {
                    // Single-line function
                    if let openBrace = line.firstIndex(of: "{"),
                       let closeBrace = line.lastIndex(of: "}"),
                       openBrace < closeBrace {
                        let bodyStart = line.index(after: openBrace)
                        bodyLines.append(String(line[bodyStart..<closeBrace]).trimmed)
                    }
                } else {
                    index += 1
                    while index < lines.count {
                        let current = lines[index]
                        braceDepth += current.filter({ $0 == "{" }).count
                        braceDepth -= current.filter({ $0 == "}" }).count
                        if braceDepth <= 0 { break }
                        bodyLines.append(current)
                        index += 1
                    }
                }

                let body = stripCommonIndentation(bodyLines)
                results.append((name, body, description))
            }

            index += 1
        }

        return results
    }

    private func stripCommonIndentation(_ lines: [String]) -> String {
        let nonEmpty = lines.filter { !$0.trimmed.isEmpty }
        guard !nonEmpty.isEmpty else { return lines.joined(separator: "\n") }
        let minIndent = nonEmpty.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        if minIndent == 0 { return lines.joined(separator: "\n") }
        return lines.map { line in
            if line.trimmed.isEmpty { return "" }
            return String(line.dropFirst(min(minIndent, line.count)))
        }.joined(separator: "\n")
    }

    // MARK: - Private

    private func markDirty() {
        hasUnsavedChanges = true
    }
}
