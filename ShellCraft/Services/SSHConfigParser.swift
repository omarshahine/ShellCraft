import Foundation

struct SSHConfigParser {

    private static let configPath = "~/.ssh/config"

    /// Known SSH config options that map to SSHHost properties directly.
    private static let knownDirectOptions: Set<String> = [
        "hostname", "user", "identityfile", "port"
    ]

    // MARK: - Parse

    /// Parses `~/.ssh/config` into an array of `SSHHost` entries.
    static func parse() throws -> [SSHHost] {
        let path = configPath.expandingTildeInPath
        guard FileIOService.fileExists(at: path) else {
            return []
        }

        let content = try FileIOService.readFile(at: path)
        return parse(content: content)
    }

    /// Parses SSH config text content into host entries.
    static func parse(content: String) -> [SSHHost] {
        let lines = content.components(separatedBy: "\n")
        var hosts: [SSHHost] = []
        var currentHost: String?
        var currentOptions: [(key: String, value: String)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Detect Host directives
            if trimmed.lowercased().hasPrefix("host ") {
                // Flush the previous host block
                if let host = currentHost {
                    hosts.append(buildSSHHost(host: host, options: currentOptions))
                }

                currentHost = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                currentOptions = []
                continue
            }

            // Detect Match blocks (treat similarly to Host)
            if trimmed.lowercased().hasPrefix("match ") {
                if let host = currentHost {
                    hosts.append(buildSSHHost(host: host, options: currentOptions))
                }
                currentHost = trimmed  // Keep the full "Match ..." as the host pattern
                currentOptions = []
                continue
            }

            // Option lines inside a Host block
            if currentHost != nil {
                if let (key, value) = parseOptionLine(trimmed) {
                    currentOptions.append((key: key, value: value))
                }
            }
        }

        // Flush the last host block
        if let host = currentHost {
            hosts.append(buildSSHHost(host: host, options: currentOptions))
        }

        return hosts
    }

    /// Parses a single option line like `HostName example.com` or `Port 22`.
    /// Supports both space-separated and `=`-separated forms.
    private static func parseOptionLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Handle Key=Value form
        if let equalsIndex = trimmed.firstIndex(of: "=") {
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return (key, value)
        }

        // Handle Key Value form (split on first whitespace)
        let components = trimmed.split(separator: " ", maxSplits: 1)
        guard components.count == 2 else {
            // Single-word option (no value), still valid
            if components.count == 1 {
                return (String(components[0]), "")
            }
            return nil
        }

        let key = String(components[0])
        let value = String(components[1]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    /// Builds an SSHHost from a parsed host pattern and its option list.
    private static func buildSSHHost(host: String, options: [(key: String, value: String)]) -> SSHHost {
        var hostname = ""
        var user = ""
        var identityFile = ""
        var port: Int?
        var extraOptions: [String: String] = [:]

        for (key, value) in options {
            switch key.lowercased() {
            case "hostname":
                hostname = value
            case "user":
                user = value
            case "identityfile":
                identityFile = value
            case "port":
                port = Int(value)
            default:
                extraOptions[key] = value
            }
        }

        return SSHHost(
            host: host,
            hostname: hostname,
            user: user,
            identityFile: identityFile,
            port: port,
            options: extraOptions
        )
    }

    // MARK: - Write

    /// Generates SSH config file content from an array of hosts.
    static func write(hosts: [SSHHost]) -> String {
        var lines: [String] = []

        for (index, host) in hosts.enumerated() {
            // Add blank line between blocks (but not before the first)
            if index > 0 {
                lines.append("")
            }

            // Host directive
            if host.host.lowercased().hasPrefix("match ") {
                lines.append(host.host)
            } else {
                lines.append("Host \(host.host)")
            }

            // Known options first, in a conventional order
            if !host.hostname.isEmpty {
                lines.append("    HostName \(host.hostname)")
            }
            if !host.user.isEmpty {
                lines.append("    User \(host.user)")
            }
            if let port = host.port {
                lines.append("    Port \(port)")
            }
            if !host.identityFile.isEmpty {
                lines.append("    IdentityFile \(host.identityFile)")
            }

            // Extra options sorted alphabetically for consistency
            for key in host.options.keys.sorted() {
                if let value = host.options[key], !value.isEmpty {
                    lines.append("    \(key) \(value)")
                } else {
                    lines.append("    \(key)")
                }
            }
        }

        // Ensure trailing newline
        if !lines.isEmpty {
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Save

    /// Writes hosts back to `~/.ssh/config`.
    static func save(hosts: [SSHHost]) throws {
        let content = write(hosts: hosts)
        try FileIOService.writeFile(at: configPath, content: content, backup: true)
    }
}
