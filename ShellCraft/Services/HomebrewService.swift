import Foundation

// MARK: - Brew JSON Response Types

/// Top-level response from `brew list --json=v2` and `brew info --json=v2`
private struct BrewListResponse: Codable {
    let formulae: [BrewFormula]?
    let casks: [BrewCask]?
}

private struct BrewFormula: Codable {
    let name: String
    let full_name: String?
    let desc: String?
    let versions: BrewVersions?
    let installed: [BrewInstalledVersion]?
}

private struct BrewVersions: Codable {
    let stable: String?
    let head: String?
}

private struct BrewInstalledVersion: Codable {
    let version: String?
}

private struct BrewCask: Codable {
    let token: String
    let name: [String]?
    let desc: String?
    let version: String?
    let installed: String?
}

/// Response from `brew search --json`
private struct BrewSearchResponse: Codable {
    let formulae: [BrewFormula]?
    let casks: [BrewCask]?
}

// MARK: - Service

struct HomebrewService {

    // MARK: - Availability

    static func isBrewInstalled() async -> Bool {
        await ProcessService.commandExists("brew")
    }

    // MARK: - List Installed

    /// Lists all installed Homebrew packages (formulae and casks).
    static func listInstalled() async throws -> [HomebrewPackage] {
        // Homebrew 5.x removed --json from `brew list`; use `brew info --installed` instead.
        let result = try await ProcessService.run("brew info --json=v2 --installed")
        guard result.succeeded else {
            throw HomebrewError.commandFailed("brew info --installed", result.error)
        }

        guard let data = result.output.data(using: .utf8) else {
            throw HomebrewError.parseFailed("Invalid UTF-8 output from brew list")
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(BrewListResponse.self, from: data)

        var packages: [HomebrewPackage] = []

        // Parse formulae
        if let formulae = response.formulae {
            for formula in formulae {
                let version = formula.installed?.first?.version
                    ?? formula.versions?.stable
                    ?? ""
                packages.append(HomebrewPackage(
                    name: formula.name,
                    version: version,
                    isFormula: true,
                    description: formula.desc ?? "",
                    isInstalled: true
                ))
            }
        }

        // Parse casks
        if let casks = response.casks {
            for cask in casks {
                packages.append(HomebrewPackage(
                    name: cask.token,
                    version: cask.installed ?? cask.version ?? "",
                    isFormula: false,
                    description: cask.desc ?? "",
                    isInstalled: true
                ))
            }
        }

        return packages.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Search

    /// Searches for packages matching a query string.
    static func search(query: String) async throws -> [HomebrewPackage] {
        guard !query.trimmed.isEmpty else { return [] }

        let escapedQuery = query.trimmed.singleQuoted
        let result = try await ProcessService.run("brew search --json \(escapedQuery)")
        guard result.succeeded else {
            throw HomebrewError.commandFailed("brew search", result.error)
        }

        guard let data = result.output.data(using: .utf8) else {
            throw HomebrewError.parseFailed("Invalid UTF-8 output from brew search")
        }

        let decoder = JSONDecoder()

        // brew search --json returns either an array of formula objects or just names.
        // Try structured format first.
        var packages: [HomebrewPackage] = []

        if let response = try? decoder.decode(BrewSearchResponse.self, from: data) {
            if let formulae = response.formulae {
                for formula in formulae {
                    let version = formula.versions?.stable ?? ""
                    packages.append(HomebrewPackage(
                        name: formula.name,
                        version: version,
                        isFormula: true,
                        description: formula.desc ?? "",
                        isInstalled: formula.installed?.isEmpty == false
                    ))
                }
            }
            if let casks = response.casks {
                for cask in casks {
                    packages.append(HomebrewPackage(
                        name: cask.token,
                        version: cask.version ?? "",
                        isFormula: false,
                        description: cask.desc ?? "",
                        isInstalled: cask.installed != nil
                    ))
                }
            }
        } else if let nameArrays = try? decoder.decode(BrewSearchNameArrays.self, from: data) {
            // Fallback: brew search --json may return {"formulae":["name1","name2"],"casks":["name3"]}
            for name in nameArrays.formulae ?? [] {
                packages.append(HomebrewPackage(
                    name: name,
                    version: "",
                    isFormula: true,
                    description: "",
                    isInstalled: false
                ))
            }
            for name in nameArrays.casks ?? [] {
                packages.append(HomebrewPackage(
                    name: name,
                    version: "",
                    isFormula: false,
                    description: "",
                    isInstalled: false
                ))
            }
        }

        return packages.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Install

    /// Installs a package using brew.
    static func install(package name: String, isCask: Bool = false) async throws {
        let caskFlag = isCask ? " --cask" : ""
        let result = try await ProcessService.run("brew install\(caskFlag) \(name.singleQuoted)")
        guard result.succeeded else {
            throw HomebrewError.commandFailed("brew install \(name)", result.error)
        }
    }

    // MARK: - Uninstall

    /// Uninstalls a package using brew.
    static func uninstall(package name: String, isCask: Bool = false) async throws {
        let caskFlag = isCask ? " --cask" : ""
        let result = try await ProcessService.run("brew uninstall\(caskFlag) \(name.singleQuoted)")
        guard result.succeeded else {
            throw HomebrewError.commandFailed("brew uninstall \(name)", result.error)
        }
    }

    // MARK: - Info

    /// Gets detailed info about a single package.
    static func info(package name: String) async throws -> HomebrewPackage {
        let result = try await ProcessService.run("brew info --json=v2 \(name.singleQuoted)")
        guard result.succeeded else {
            throw HomebrewError.commandFailed("brew info \(name)", result.error)
        }

        guard let data = result.output.data(using: .utf8) else {
            throw HomebrewError.parseFailed("Invalid UTF-8 output from brew info")
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(BrewListResponse.self, from: data)

        // Check formulae first
        if let formula = response.formulae?.first {
            let installedVersion = formula.installed?.first?.version
            let version = installedVersion ?? formula.versions?.stable ?? ""
            let isInstalled = formula.installed?.isEmpty == false
            return HomebrewPackage(
                name: formula.name,
                version: version,
                isFormula: true,
                description: formula.desc ?? "",
                isInstalled: isInstalled
            )
        }

        // Check casks
        if let cask = response.casks?.first {
            return HomebrewPackage(
                name: cask.token,
                version: cask.installed ?? cask.version ?? "",
                isFormula: false,
                description: cask.desc ?? "",
                isInstalled: cask.installed != nil
            )
        }

        throw HomebrewError.packageNotFound(name)
    }
}

// MARK: - Fallback Search Type

/// Fallback type for when brew search --json returns simple name arrays
private struct BrewSearchNameArrays: Codable {
    let formulae: [String]?
    let casks: [String]?
}

// MARK: - Errors

enum HomebrewError: LocalizedError {
    case commandFailed(String, String)
    case parseFailed(String)
    case packageNotFound(String)
    case brewNotInstalled

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let error):
            "'\(command)' failed: \(error)"
        case .parseFailed(let detail):
            "Failed to parse Homebrew output: \(detail)"
        case .packageNotFound(let name):
            "Package '\(name)' not found"
        case .brewNotInstalled:
            "Homebrew is not installed. Visit https://brew.sh to install."
        }
    }
}
