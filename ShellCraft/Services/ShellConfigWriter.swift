import Foundation

struct ShellConfigWriter {

    // MARK: - Modification Types

    enum Modification: Sendable {
        case updateLine(Int, String)        // line index (0-based), new content
        case insertAfter(Int, String)       // insert after line index (0-based), content
        case deleteLine(Int)                // line index (0-based)
        case appendLine(String)             // append to end of file
    }

    // MARK: - Apply Modifications

    /// Applies a batch of modifications to a raw lines array.
    /// Modifications are sorted and applied in reverse order so that
    /// line-number shifts from insertions/deletions don't affect earlier entries.
    static func apply(modifications: [Modification], to lines: [String]) -> [String] {
        var result = lines

        // Sort modifications by their primary line index in descending order
        // so changes at higher indices are applied first
        let sorted = modifications.sorted { lhs, rhs in
            lineIndex(of: lhs) > lineIndex(of: rhs)
        }

        for modification in sorted {
            switch modification {
            case .updateLine(let index, let newContent):
                guard index >= 0 && index < result.count else { continue }
                result[index] = newContent

            case .insertAfter(let index, let content):
                let insertionIndex = min(index + 1, result.count)
                result.insert(content, at: insertionIndex)

            case .deleteLine(let index):
                guard index >= 0 && index < result.count else { continue }
                result.remove(at: index)

            case .appendLine(let content):
                result.append(content)
            }
        }

        return result
    }

    private static func lineIndex(of modification: Modification) -> Int {
        switch modification {
        case .updateLine(let index, _): index
        case .insertAfter(let index, _): index
        case .deleteLine(let index): index
        case .appendLine: Int.max // always last
        }
    }

    // MARK: - Line Generation

    /// Generates an alias line: `alias name='expansion'`
    static func generateAliasLine(name: String, expansion: String, enabled: Bool = true) -> String {
        let prefix = enabled ? "" : "# "
        // Use single quotes unless the expansion contains single quotes
        if expansion.contains("'") {
            return "\(prefix)alias \(name)=\"\(expansion)\""
        }
        return "\(prefix)alias \(name)='\(expansion)'"
    }

    /// Generates a commented-out alias line: `# alias name='expansion'`
    static func generateDisabledAliasLine(name: String, expansion: String) -> String {
        generateAliasLine(name: name, expansion: expansion, enabled: false)
    }

    /// Generates a function block
    static func generateFunctionBlock(name: String, body: String) -> String {
        let indentedBody = body.components(separatedBy: "\n").map { line in
            line.isEmpty ? "" : "  \(line)"
        }.joined(separator: "\n")
        return "\(name)() {\n\(indentedBody)\n}"
    }

    /// Generates an export line: `export KEY="value"`
    static func generateExportLine(key: String, value: String) -> String {
        // If value contains $( ) subshell or variable references, don't quote with single quotes
        if value.contains("$(") || value.contains("`") {
            return "export \(key)=\(value)"
        }
        return "export \(key)=\"\(value)\""
    }

    /// Generates a keychain-derived export line
    static func generateKeychainExportLine(key: String, keychainService: String) -> String {
        "export \(key)=$(security find-generic-password -s '\(keychainService)' -a \"$USER\" -w)"
    }

    /// Generates a PATH export line from ordered entries.
    /// Produces: `export PATH="/path/one:/path/two:$PATH"`
    static func generatePathExportLine(entries: [PathEntry]) -> String {
        let paths = entries
            .sorted(by: { $0.order < $1.order })
            .map(\.path)
            .joined(separator: ":")
        return "export PATH=\"\(paths):$PATH\""
    }

    // MARK: - High-Level Write Operations

    /// Writes modified lines back to a file
    static func writeLines(_ lines: [String], to path: String) throws {
        let content = lines.joined(separator: "\n")
        try FileIOService.writeFile(at: path, content: content)
    }

    /// Applies modifications and writes the result to the file
    static func applyAndWrite(modifications: [Modification], to path: String) throws {
        let currentLines = try FileIOService.readLines(at: path)
        let updatedLines = apply(modifications: modifications, to: currentLines)
        try writeLines(updatedLines, to: path)
    }

    // MARK: - Alias Operations

    /// Updates an existing alias at its known line number
    static func updateAlias(_ alias: ShellAlias, in lines: inout [String]) {
        let lineIndex = alias.lineNumber - 1 // convert to 0-based
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        lines[lineIndex] = generateAliasLine(
            name: alias.name,
            expansion: alias.expansion,
            enabled: alias.isEnabled
        )
    }

    /// Removes an alias at its known line number
    static func deleteAlias(_ alias: ShellAlias, from lines: inout [String]) {
        let lineIndex = alias.lineNumber - 1
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        lines.remove(at: lineIndex)
    }

    /// Appends a new alias to the end of the file
    static func appendAlias(name: String, expansion: String, to lines: inout [String]) {
        let aliasLine = generateAliasLine(name: name, expansion: expansion)
        lines.append(aliasLine)
    }

    // MARK: - Function Operations

    /// Replaces a function at its known line range
    static func updateFunction(_ function: ShellFunction, in lines: inout [String]) {
        let startIndex = function.lineRange.lowerBound - 1 // convert to 0-based
        let endIndex = function.lineRange.upperBound - 1

        guard startIndex >= 0 && endIndex < lines.count else { return }

        let newBlock = generateFunctionBlock(name: function.name, body: function.body)
        let newLines = newBlock.components(separatedBy: "\n")

        // Remove old range and insert new
        lines.removeSubrange(startIndex...endIndex)
        lines.insert(contentsOf: newLines, at: startIndex)
    }

    /// Removes a function at its known line range
    static func deleteFunction(_ function: ShellFunction, from lines: inout [String]) {
        let startIndex = function.lineRange.lowerBound - 1
        let endIndex = function.lineRange.upperBound - 1
        guard startIndex >= 0 && endIndex < lines.count else { return }
        lines.removeSubrange(startIndex...endIndex)
    }

    /// Appends a new function to the end of the file
    static func appendFunction(name: String, body: String, description: String, to lines: inout [String]) {
        lines.append("") // blank line before function
        if !description.isEmpty {
            lines.append("# \(description)")
        }
        let block = generateFunctionBlock(name: name, body: body)
        lines.append(contentsOf: block.components(separatedBy: "\n"))
    }

    // MARK: - Environment Variable Operations

    /// Updates an environment variable at its known line number
    static func updateEnvVar(_ envVar: EnvironmentVariable, in lines: inout [String]) {
        let lineIndex = envVar.lineNumber - 1
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        lines[lineIndex] = generateExportLine(key: envVar.key, value: envVar.value)
    }

    /// Removes an environment variable at its known line number
    static func deleteEnvVar(_ envVar: EnvironmentVariable, from lines: inout [String]) {
        let lineIndex = envVar.lineNumber - 1
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        lines.remove(at: lineIndex)
    }

    /// Appends a new environment variable
    static func appendEnvVar(key: String, value: String, isKeychain: Bool, to lines: inout [String]) {
        if isKeychain {
            let serviceName = "env/\(key)"
            lines.append(generateKeychainExportLine(key: key, keychainService: serviceName))
        } else {
            lines.append(generateExportLine(key: key, value: value))
        }
    }
}
