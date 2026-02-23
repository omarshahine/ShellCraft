import Foundation

@MainActor @Observable
final class HomebrewViewModel {

    // MARK: - Filter

    enum PackageFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case formulae = "Formulae"
        case casks = "Casks"
        case installed = "Installed"

        var id: String { rawValue }
    }

    // MARK: - Published State

    var packages: [HomebrewPackage] = []
    var searchText: String = ""
    var searchResults: [HomebrewPackage] = []
    var isLoading: Bool = false
    var filter: PackageFilter = .all
    var errorMessage: String? = nil
    var isBrewAvailable: Bool = false
    var isSearching: Bool = false

    /// Track which package is pending uninstall confirmation
    var packagePendingUninstall: HomebrewPackage? = nil

    /// Track which package is currently being installed/uninstalled (for progress)
    var operationInProgress: String? = nil

    // MARK: - Computed

    var filteredPackages: [HomebrewPackage] {
        let source = searchText.isEmpty ? packages : searchResults

        return source.filter { package in
            switch filter {
            case .all:
                return true
            case .formulae:
                return package.isFormula
            case .casks:
                return !package.isFormula
            case .installed:
                return package.isInstalled
            }
        }
    }

    var installedCount: Int {
        packages.filter(\.isInstalled).count
    }

    var formulaeCount: Int {
        packages.filter(\.isFormula).count
    }

    var caskCount: Int {
        packages.filter { !$0.isFormula }.count
    }

    // MARK: - Load

    func load() {
        isLoading = true
        errorMessage = nil

        Task {
            let brewAvailable = await HomebrewService.isBrewInstalled()

            await MainActor.run {
                self.isBrewAvailable = brewAvailable
            }

            guard brewAvailable else {
                await MainActor.run {
                    self.errorMessage = HomebrewError.brewNotInstalled.errorDescription
                    self.isLoading = false
                }
                return
            }

            do {
                let installed = try await HomebrewService.listInstalled()
                await MainActor.run {
                    self.packages = installed
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load packages: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Search

    func search() {
        let query = searchText.trimmed
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        Task {
            do {
                let results = try await HomebrewService.search(query: query)

                // Merge with installed state: if a search result matches an installed package,
                // carry over the isInstalled flag.
                let installedNames = Set(packages.map(\.name))
                let merged = results.map { result in
                    var pkg = result
                    if installedNames.contains(pkg.name) {
                        pkg = HomebrewPackage(
                            id: pkg.id,
                            name: pkg.name,
                            version: pkg.version,
                            isFormula: pkg.isFormula,
                            description: pkg.description,
                            isInstalled: true
                        )
                    }
                    return pkg
                }

                await MainActor.run {
                    self.searchResults = merged
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Search failed: \(error.localizedDescription)"
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - Install

    func install(_ package: HomebrewPackage) {
        operationInProgress = package.name
        errorMessage = nil

        Task {
            do {
                try await HomebrewService.install(
                    package: package.name,
                    isCask: !package.isFormula
                )

                // Refresh the installed list
                let installed = try await HomebrewService.listInstalled()

                await MainActor.run {
                    self.packages = installed
                    self.operationInProgress = nil

                    // Update search results to reflect installed state
                    if !self.searchResults.isEmpty {
                        self.updateSearchResultInstallState(name: package.name, installed: true)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Install failed: \(error.localizedDescription)"
                    self.operationInProgress = nil
                }
            }
        }
    }

    // MARK: - Uninstall

    func confirmUninstall(_ package: HomebrewPackage) {
        packagePendingUninstall = package
    }

    func cancelUninstall() {
        packagePendingUninstall = nil
    }

    func uninstall(_ package: HomebrewPackage) {
        packagePendingUninstall = nil
        operationInProgress = package.name
        errorMessage = nil

        Task {
            do {
                try await HomebrewService.uninstall(
                    package: package.name,
                    isCask: !package.isFormula
                )

                // Refresh the installed list
                let installed = try await HomebrewService.listInstalled()

                await MainActor.run {
                    self.packages = installed
                    self.operationInProgress = nil

                    // Update search results to reflect uninstalled state
                    if !self.searchResults.isEmpty {
                        self.updateSearchResultInstallState(name: package.name, installed: false)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Uninstall failed: \(error.localizedDescription)"
                    self.operationInProgress = nil
                }
            }
        }
    }

    // MARK: - Import / Export

    /// Exports installed packages as a Brewfile.
    func exportData() -> String {
        var lines: [String] = []
        lines.append("# ShellCraft Brewfile Export")
        lines.append("# Generated \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        let formulae = packages.filter { $0.isFormula && $0.isInstalled }
            .sorted { $0.name < $1.name }
        let casks = packages.filter { !$0.isFormula && $0.isInstalled }
            .sorted { $0.name < $1.name }

        if !formulae.isEmpty {
            lines.append("# Formulae")
            for pkg in formulae {
                lines.append("brew \"\(pkg.name)\"")
            }
            lines.append("")
        }

        if !casks.isEmpty {
            lines.append("# Casks")
            for pkg in casks {
                lines.append("cask \"\(pkg.name)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Homebrew import runs `brew bundle` directly — no SaveBar step.
    func importBrewfile(at url: URL) {
        operationInProgress = "brew bundle"
        errorMessage = nil

        Task {
            do {
                let result = try await ProcessService.run(
                    "brew bundle install --file=\(url.path.singleQuoted)"
                )
                if !result.succeeded {
                    await MainActor.run {
                        self.errorMessage = "brew bundle failed: \(result.error)"
                    }
                }

                // Refresh package list
                let installed = try await HomebrewService.listInstalled()
                await MainActor.run {
                    self.packages = installed
                    self.operationInProgress = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "brew bundle failed: \(error.localizedDescription)"
                    self.operationInProgress = nil
                }
            }
        }
    }

    // MARK: - Private

    private func updateSearchResultInstallState(name: String, installed: Bool) {
        if let index = searchResults.firstIndex(where: { $0.name == name }) {
            let old = searchResults[index]
            searchResults[index] = HomebrewPackage(
                id: old.id,
                name: old.name,
                version: old.version,
                isFormula: old.isFormula,
                description: old.description,
                isInstalled: installed
            )
        }
    }
}
