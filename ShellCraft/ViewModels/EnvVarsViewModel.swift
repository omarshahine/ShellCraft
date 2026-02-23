import Foundation

@MainActor @Observable
final class EnvVarsViewModel {

    // MARK: - Published State

    var variables: [EnvironmentVariable] = []
    var searchText: String = ""
    var hasUnsavedChanges: Bool = false
    var errorMessage: String? = nil
    var isLoading: Bool = false

    // MARK: - Internal State

    private var rawLines: [String: [String]] = [:]
    private var savedSnapshot: [EnvironmentVariable] = []

    // MARK: - Computed

    var filteredVariables: [EnvironmentVariable] {
        let base = variables.filter { $0.key != "PATH" }
        guard !searchText.isEmpty else { return base }
        return base.filter { variable in
            variable.key.localizedCaseInsensitiveContains(searchText) ||
            variable.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    var keychainVariableCount: Int {
        variables.filter(\.isKeychainDerived).count
    }

    // MARK: - Load

    func load() {
        isLoading = true
        errorMessage = nil

        do {
            let config = try ShellConfigParser.parse()
            variables = config.environmentVariables
            rawLines = config.rawLines
            savedSnapshot = variables
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to parse environment variables: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Save

    func save() {
        errorMessage = nil

        do {
            let varsByFile = Dictionary(grouping: variables, by: \.sourceFile)

            for (file, fileVars) in varsByFile {
                guard var lines = rawLines[file] else { continue }

                var modifications: [ShellConfigWriter.Modification] = []

                // Update existing variables
                let savedIDs = Set(savedSnapshot.map(\.id))
                for variable in fileVars where savedIDs.contains(variable.id) {
                    if let original = savedSnapshot.first(where: { $0.id == variable.id }) {
                        let lineIndex = original.lineNumber - 1
                        let newLine: String
                        if variable.isKeychainDerived {
                            // Keychain-derived vars: if only the key changed, regenerate
                            // the keychain export with the conventional service name.
                            // The value contains the $(security ...) command substitution
                            // which generateExportLine preserves (it detects $( and skips quoting).
                            if variable.key != original.key {
                                let serviceName = "env/\(variable.key)"
                                newLine = ShellConfigWriter.generateKeychainExportLine(
                                    key: variable.key,
                                    keychainService: serviceName
                                )
                            } else {
                                newLine = ShellConfigWriter.generateExportLine(
                                    key: variable.key,
                                    value: variable.value
                                )
                            }
                        } else {
                            newLine = ShellConfigWriter.generateExportLine(
                                key: variable.key,
                                value: variable.value
                            )
                        }
                        modifications.append(.updateLine(lineIndex, newLine))
                    }
                }

                // Delete removed variables
                let currentIDs = Set(variables.map(\.id))
                let deletedVars = savedSnapshot.filter { saved in
                    saved.sourceFile == file && !currentIDs.contains(saved.id)
                }
                for deleted in deletedVars {
                    modifications.append(.deleteLine(deleted.lineNumber - 1))
                }

                // Append new variables
                let newVars = fileVars.filter { !savedIDs.contains($0.id) }
                for newVar in newVars {
                    if newVar.isKeychainDerived {
                        let serviceName = "env/\(newVar.key)"
                        let line = ShellConfigWriter.generateKeychainExportLine(
                            key: newVar.key,
                            keychainService: serviceName
                        )
                        modifications.append(.appendLine(line))
                    } else {
                        let line = ShellConfigWriter.generateExportLine(
                            key: newVar.key,
                            value: newVar.value
                        )
                        modifications.append(.appendLine(line))
                    }
                }

                lines = ShellConfigWriter.apply(modifications: modifications, to: lines)
                try ShellConfigWriter.writeLines(lines, to: file)
            }

            // Handle new variables targeting default file
            let savedIDs = Set(savedSnapshot.map(\.id))
            let newDefaultVars = variables.filter {
                !savedIDs.contains($0.id) && varsByFile[$0.sourceFile] == nil
            }
            if !newDefaultVars.isEmpty {
                let defaultFile = "~/.zshrc"
                var lines = rawLines[defaultFile] ?? (try? FileIOService.readLines(at: defaultFile)) ?? []
                for newVar in newDefaultVars {
                    ShellConfigWriter.appendEnvVar(
                        key: newVar.key,
                        value: newVar.value,
                        isKeychain: newVar.isKeychainDerived,
                        to: &lines
                    )
                }
                try ShellConfigWriter.writeLines(lines, to: defaultFile)
            }

            // Reload for fresh line numbers
            load()
        } catch {
            errorMessage = "Failed to save environment variables: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    func add(key: String, value: String, isKeychain: Bool = false) {
        let variable = EnvironmentVariable(
            key: key,
            value: value,
            sourceFile: "~/.zshrc",
            lineNumber: 0,
            isKeychainDerived: isKeychain
        )
        variables.append(variable)
        markDirty()
    }

    func update(_ variable: EnvironmentVariable) {
        guard let index = variables.firstIndex(where: { $0.id == variable.id }) else { return }
        variables[index] = variable
        markDirty()
    }

    func delete(_ variable: EnvironmentVariable) {
        variables.removeAll { $0.id == variable.id }
        markDirty()
    }

    // MARK: - Discard

    func discard() {
        variables = savedSnapshot
        hasUnsavedChanges = false
    }

    // MARK: - Import / Export

    func exportData() -> String {
        var output = ImportExportService.shellHeader(section: "Environment Variables")
        for variable in variables where variable.key != "PATH" {
            if variable.isKeychainDerived {
                output += ShellConfigWriter.generateKeychainExportLine(
                    key: variable.key,
                    keychainService: "env/\(variable.key)"
                ) + "\n"
            } else {
                output += ShellConfigWriter.generateExportLine(
                    key: variable.key,
                    value: variable.value
                ) + "\n"
            }
        }
        return output
    }

    func previewImport(_ content: String) -> ImportPreview {
        let lines = content.components(separatedBy: "\n")
        var newItems: [String] = []
        var updatedItems: [String] = []
        var unchanged = 0

        for line in lines {
            guard let parsed = ShellLineParser.parseExport(from: line),
                  parsed.key != "PATH" else { continue }

            if let existing = variables.first(where: { $0.key == parsed.key }) {
                if existing.value != parsed.value {
                    updatedItems.append(parsed.key)
                } else {
                    unchanged += 1
                }
            } else {
                newItems.append(parsed.key)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "Environment Variables",
            isReplace: false,
            newItems: newItems,
            updatedItems: updatedItems,
            unchangedCount: unchanged,
            warnings: []
        )
    }

    func applyImport(_ content: String) {
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            guard let parsed = ShellLineParser.parseExport(from: line),
                  parsed.key != "PATH" else { continue }

            let isKeychain = ShellLineParser.isKeychainDerived(parsed.value)

            if let index = variables.firstIndex(where: { $0.key == parsed.key }) {
                variables[index].value = parsed.value
                variables[index].isKeychainDerived = isKeychain
            } else {
                let variable = EnvironmentVariable(
                    key: parsed.key,
                    value: parsed.value,
                    sourceFile: "~/.zshrc",
                    lineNumber: 0,
                    isKeychainDerived: isKeychain
                )
                variables.append(variable)
            }
        }

        markDirty()
    }

    // MARK: - Private

    private func markDirty() {
        hasUnsavedChanges = true
    }
}
