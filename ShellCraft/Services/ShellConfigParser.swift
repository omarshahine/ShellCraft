import Foundation

/// Result of parsing shell configuration files
struct ParsedShellConfig {
    var aliases: [ShellAlias]
    var functions: [ShellFunction]
    var pathEntries: [PathEntry]
    var environmentVariables: [EnvironmentVariable]
    var rawLines: [String: [String]] // file path -> lines

    init() {
        aliases = []
        functions = []
        pathEntries = []
        environmentVariables = []
        rawLines = [:]
    }
}

struct ShellConfigParser {

    // MARK: - Configuration

    static let defaultFiles: [String] = [
        "~/.zshrc",
        "~/.zprofile"
    ]

    // MARK: - Full Parse

    /// Parses all default shell config files and returns a combined result,
    /// following `source` / `.` directives to discover aliases in sourced files.
    static func parse(files: [String] = defaultFiles) throws -> ParsedShellConfig {
        var config = ParsedShellConfig()
        var visitedFiles: Set<String> = []

        for file in files {
            let expandedPath = file.expandingTildeInPath
            guard FileIOService.fileExists(at: file) else { continue }
            visitedFiles.insert(expandedPath)
            let lines = try FileIOService.readLines(at: file)
            config.rawLines[file] = lines
            parseFile(lines: lines, sourceFile: file, into: &config, visitedFiles: &visitedFiles)
        }

        return config
    }

    /// Parses a single file given its path
    static func parseSingleFile(_ path: String) throws -> ParsedShellConfig {
        var config = ParsedShellConfig()
        var visitedFiles: Set<String> = []
        let expandedPath = path.expandingTildeInPath
        guard FileIOService.fileExists(at: path) else { return config }
        visitedFiles.insert(expandedPath)
        let lines = try FileIOService.readLines(at: path)
        config.rawLines[path] = lines
        parseFile(lines: lines, sourceFile: path, into: &config, visitedFiles: &visitedFiles)
        return config
    }

    // MARK: - File Parsing

    private static func parseFile(
        lines: [String],
        sourceFile: String,
        into config: inout ParsedShellConfig,
        visitedFiles: inout Set<String>
    ) {
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let lineNumber = index + 1 // 1-based line numbers

            // Skip blank lines and standalone comments
            if ShellLineParser.isBlank(line) {
                index += 1
                continue
            }

            // Try parsing as alias
            if let alias = parseAliasLine(line, sourceFile: sourceFile, lineNumber: lineNumber) {
                config.aliases.append(alias)
                index += 1
                continue
            }

            // Try parsing as function start
            if let functionName = ShellLineParser.parseFunctionStart(from: line) {
                let (function, endIndex) = parseFunction(
                    name: functionName,
                    lines: lines,
                    startIndex: index,
                    sourceFile: sourceFile
                )
                config.functions.append(function)
                index = endIndex + 1
                continue
            }

            // Try parsing as PATH export
            if let pathEntries = parsePathLine(line, sourceFile: sourceFile, lineNumber: lineNumber) {
                config.pathEntries.append(contentsOf: pathEntries)
                index += 1
                continue
            }

            // Try parsing as environment variable export (non-PATH)
            if let envVar = parseEnvVarLine(line, sourceFile: sourceFile, lineNumber: lineNumber) {
                config.environmentVariables.append(envVar)
                index += 1
                continue
            }

            // Try parsing as source/dot command to follow sourced files
            if let resolvedPath = ShellLineParser.parseSource(from: line) {
                if !visitedFiles.contains(resolvedPath),
                   FileManager.default.fileExists(atPath: resolvedPath) {
                    visitedFiles.insert(resolvedPath)
                    // Use tilde-contracted path for rawLines key consistency
                    let tildeKey = resolvedPath.abbreviatingWithTildeInPath
                    if let sourcedLines = try? FileIOService.readLines(at: tildeKey) {
                        config.rawLines[tildeKey] = sourcedLines
                        parseFile(
                            lines: sourcedLines,
                            sourceFile: tildeKey,
                            into: &config,
                            visitedFiles: &visitedFiles
                        )
                    }
                }
            }

            index += 1
        }
    }

    // MARK: - Alias Parsing

    private static func parseAliasLine(_ line: String, sourceFile: String, lineNumber: Int) -> ShellAlias? {
        guard let parsed = ShellLineParser.parseAlias(from: line) else { return nil }
        let category = AliasCategory.infer(from: parsed.name, expansion: parsed.expansion)
        return ShellAlias(
            name: parsed.name,
            expansion: parsed.expansion,
            sourceFile: sourceFile,
            lineNumber: lineNumber,
            category: category,
            isEnabled: parsed.enabled
        )
    }

    // MARK: - Function Parsing (Brace-Depth Tracking)

    private static func parseFunction(
        name: String,
        lines: [String],
        startIndex: Int,
        sourceFile: String
    ) -> (ShellFunction, endIndex: Int) {
        var braceDepth = 0
        var bodyLines: [String] = []
        var endIndex = startIndex

        // Count the opening brace on the start line
        let startLine = lines[startIndex]
        braceDepth += startLine.filter({ $0 == "{" }).count
        braceDepth -= startLine.filter({ $0 == "}" }).count

        // If the entire function is on one line (braceDepth back to 0)
        if braceDepth == 0 {
            // Extract body between { and }
            if let openBrace = startLine.firstIndex(of: "{"),
               let closeBrace = startLine.lastIndex(of: "}") {
                let bodyStart = startLine.index(after: openBrace)
                if bodyStart < closeBrace {
                    let body = String(startLine[bodyStart..<closeBrace]).trimmed
                    bodyLines.append(body)
                }
            }
            let body = bodyLines.joined(separator: "\n")
            let lineRange = (startIndex + 1)...(startIndex + 1)
            return (ShellFunction(
                name: name,
                body: body,
                sourceFile: sourceFile,
                lineRange: lineRange,
                description: extractDescription(from: lines, before: startIndex)
            ), startIndex)
        }

        // Multi-line function: collect body lines until braceDepth returns to 0
        var currentIndex = startIndex + 1
        while currentIndex < lines.count {
            let currentLine = lines[currentIndex]
            braceDepth += currentLine.filter({ $0 == "{" }).count
            braceDepth -= currentLine.filter({ $0 == "}" }).count

            if braceDepth <= 0 {
                // Don't include the closing brace line in the body
                endIndex = currentIndex
                break
            } else {
                bodyLines.append(currentLine)
            }
            currentIndex += 1
        }

        // If we never found the closing brace, use the last line
        if braceDepth > 0 {
            endIndex = lines.count - 1
        }

        // Strip common leading whitespace from body
        let body = stripCommonIndentation(bodyLines)
        let lineRange = (startIndex + 1)...(endIndex + 1) // 1-based

        return (ShellFunction(
            name: name,
            body: body,
            sourceFile: sourceFile,
            lineRange: lineRange,
            description: extractDescription(from: lines, before: startIndex)
        ), endIndex)
    }

    /// Looks for a comment immediately above the function to use as a description
    private static func extractDescription(from lines: [String], before index: Int) -> String {
        guard index > 0 else { return "" }
        let previousLine = lines[index - 1].trimmed
        if previousLine.hasPrefix("#") {
            return String(previousLine.dropFirst()).trimmed
        }
        return ""
    }

    /// Strips the common leading whitespace from a set of lines
    private static func stripCommonIndentation(_ lines: [String]) -> String {
        let nonEmptyLines = lines.filter { !$0.trimmed.isEmpty }
        guard !nonEmptyLines.isEmpty else { return lines.joined(separator: "\n") }

        let minIndent = nonEmptyLines.map { line -> Int in
            line.prefix(while: { $0 == " " || $0 == "\t" }).count
        }.min() ?? 0

        if minIndent == 0 { return lines.joined(separator: "\n") }

        return lines.map { line in
            if line.trimmed.isEmpty { return "" }
            return String(line.dropFirst(min(minIndent, line.count)))
        }.joined(separator: "\n")
    }

    // MARK: - PATH Parsing

    private static func parsePathLine(_ line: String, sourceFile: String, lineNumber: Int) -> [PathEntry]? {
        let trimmed = line.trimmed

        // Match: export PATH="..."  or  export PATH=...
        if let match = trimmed.wholeMatch(of: ShellLineParser.pathExportPattern) {
            let pathValue = ShellLineParser.unquote(String(match.1))
            return splitPathEntries(pathValue, sourceFile: sourceFile)
        }

        // Match: PATH="newpath:$PATH"
        if let match = trimmed.wholeMatch(of: ShellLineParser.pathPrependPattern) {
            let newPath = String(match.1)
            return [PathEntry(
                path: newPath,
                order: 0,
                sourceFile: sourceFile
            )]
        }

        return nil
    }

    /// Splits a PATH value like "/usr/bin:/usr/local/bin:$PATH" into individual entries,
    /// filtering out $PATH references
    private static func splitPathEntries(_ value: String, sourceFile: String) -> [PathEntry] {
        let components = value.components(separatedBy: ":")
        var entries: [PathEntry] = []
        var order = 0

        for component in components {
            // First try matched-pair unquote, then strip any remaining stray quotes.
            // Stray quotes appear when a quoted group spans multiple colon-separated
            // components, e.g. export PATH="$HOME/bin:$PATH":/usr/local/bin
            var cleaned = ShellLineParser.unquote(component.trimmed)
            cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            // Skip $PATH, ${PATH}, and empty components
            if cleaned.isEmpty || cleaned == "$PATH" || cleaned == "${PATH}" {
                continue
            }
            entries.append(PathEntry(
                path: cleaned,
                order: order,
                sourceFile: sourceFile
            ))
            order += 1
        }

        return entries
    }

    // MARK: - Environment Variable Parsing

    private static func parseEnvVarLine(_ line: String, sourceFile: String, lineNumber: Int) -> EnvironmentVariable? {
        guard let parsed = ShellLineParser.parseExport(from: line) else { return nil }

        // Skip PATH exports — they're handled separately
        guard parsed.key != "PATH" else { return nil }

        let isKeychain = ShellLineParser.isKeychainDerived(parsed.value)

        return EnvironmentVariable(
            key: parsed.key,
            value: parsed.value,
            sourceFile: sourceFile,
            lineNumber: lineNumber,
            isKeychainDerived: isKeychain
        )
    }
}
