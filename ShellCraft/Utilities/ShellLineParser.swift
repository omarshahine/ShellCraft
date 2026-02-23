import Foundation

struct ShellLineParser {
    // MARK: - Alias Patterns
    nonisolated(unsafe) static let aliasPattern = /^alias\s+([^\s=]+)=(.+)$/
    nonisolated(unsafe) static let commentedAliasPattern = /^#\s*alias\s+([^\s=]+)=(.+)$/

    // MARK: - Function Patterns
    nonisolated(unsafe) static let functionStartPattern = /^(\w[\w-]*)\(\)\s*\{/
    nonisolated(unsafe) static let functionKeywordPattern = /^function\s+(\w[\w-]*)\s*(\(\))?\s*\{/

    // MARK: - PATH Patterns
    nonisolated(unsafe) static let pathExportPattern = /^export\s+PATH=(.+)$/
    nonisolated(unsafe) static let pathPrependPattern = /^PATH=["']?([^"':]+):\$PATH["']?$/

    // MARK: - Environment Variable Patterns
    nonisolated(unsafe) static let exportPattern = /^export\s+(\w+)=(.+)$/

    // MARK: - Source/Dot Patterns
    nonisolated(unsafe) static let sourcePattern = /^(?:source|\.)\s+(.+)$/

    // MARK: - Keychain Pattern
    nonisolated(unsafe) static let keychainPattern = /\$\(security\s+find-generic-password/

    /// Strips surrounding quotes from a value
    static func unquote(_ value: String) -> String {
        var s = value.trimmed
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Checks if a line is a comment
    static func isComment(_ line: String) -> Bool {
        line.trimmed.hasPrefix("#")
    }

    /// Checks if a line is blank
    static func isBlank(_ line: String) -> Bool {
        line.trimmed.isEmpty
    }

    /// Tries to parse an alias from a line
    static func parseAlias(from line: String) -> (name: String, expansion: String, enabled: Bool)? {
        let trimmedLine = line.trimmed

        if let match = trimmedLine.wholeMatch(of: aliasPattern) {
            let name = String(match.1)
            let expansion = unquote(String(match.2))
            return (name, expansion, true)
        }

        if let match = trimmedLine.wholeMatch(of: commentedAliasPattern) {
            let name = String(match.1)
            let expansion = unquote(String(match.2))
            return (name, expansion, false)
        }

        return nil
    }

    /// Checks if a line starts a function definition
    static func parseFunctionStart(from line: String) -> String? {
        let trimmedLine = line.trimmed
        if let match = trimmedLine.prefixMatch(of: functionStartPattern) {
            return String(match.1)
        }
        if let match = trimmedLine.prefixMatch(of: functionKeywordPattern) {
            return String(match.1)
        }
        return nil
    }

    /// Tries to parse an export from a line
    static func parseExport(from line: String) -> (key: String, value: String)? {
        let trimmedLine = line.trimmed
        guard let match = trimmedLine.wholeMatch(of: exportPattern) else { return nil }
        let key = String(match.1)
        let value = unquote(String(match.2))
        return (key, value)
    }

    /// Tries to parse a source/dot command and return the resolved file path.
    /// Handles both direct (`source file`) and conditional (`[ -f file ] && source file`) patterns.
    static func parseSource(from line: String) -> String? {
        var candidate = line.trimmed

        // Handle conditional sourcing: strip `[ ... ] && ` or `[[ ... ]] && ` prefixes
        if candidate.hasPrefix("[") {
            if let range = candidate.range(of: "&&") {
                candidate = String(candidate[range.upperBound...]).trimmed
            } else {
                return nil
            }
        }

        guard let match = candidate.prefixMatch(of: sourcePattern) else { return nil }
        var path = unquote(String(match.1))
        // Resolve common shell variables
        path = path
            .replacingOccurrences(of: "${HOME}", with: NSHomeDirectory())
            .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
        return path.expandingTildeInPath
    }

    /// Checks if a value is derived from Keychain
    static func isKeychainDerived(_ value: String) -> Bool {
        value.contains("$(security") || value.contains("$( security")
    }
}
