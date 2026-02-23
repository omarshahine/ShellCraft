import Foundation

extension String {
    /// Expands ~ to the user's home directory
    var expandingTildeInPath: String {
        if hasPrefix("~/") {
            return NSHomeDirectory() + dropFirst(1)
        }
        if self == "~" {
            return NSHomeDirectory()
        }
        return self
    }

    /// Escapes special shell characters
    var shellEscaped: String {
        let specialChars: Set<Character> = [" ", "\"", "'", "\\", "$", "`", "!", "(", ")", "{", "}", "[", "]", "&", "|", ";", "<", ">", "?", "*", "#", "~"]
        var result = ""
        for char in self {
            if specialChars.contains(char) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }

    /// Wraps string in single quotes for shell safety
    var singleQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Wraps string in double quotes for shell safety
    var doubleQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`") + "\""
    }

    /// Replaces the home directory prefix with ~ for display and storage
    var abbreviatingWithTildeInPath: String {
        let home = NSHomeDirectory()
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }

    /// Trims whitespace and newlines
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
