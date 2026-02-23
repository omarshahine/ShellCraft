import Foundation

// MARK: - Tool Recipe

/// A suggested tool that users can add to their tracked list.
struct ToolRecipe: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let brewName: String?
    let category: Category

    enum Category: String, CaseIterable, Identifiable {
        case essentials = "Essentials"
        case search = "Search & Navigation"
        case shell = "Shell Enhancements"
        case devTools = "Developer Tools"
        case containers = "Containers & Cloud"
        case editors = "Editors"

        var id: String { rawValue }
    }
}

extension ToolRecipe {
    static let catalog: [ToolRecipe] = [
        // Essentials
        ToolRecipe(name: "trash", description: "Move files to Trash instead of permanent deletion", brewName: nil, category: .essentials),
        ToolRecipe(name: "claude", description: "Claude Code CLI — AI-powered development assistant", brewName: nil, category: .essentials),
        ToolRecipe(name: "gh", description: "GitHub CLI — manage PRs, issues, and repos from terminal", brewName: "gh", category: .essentials),
        ToolRecipe(name: "jq", description: "Lightweight JSON processor for the command line", brewName: "jq", category: .essentials),

        // Search & Navigation
        ToolRecipe(name: "rg", description: "ripgrep — blazing fast recursive search (faster than grep)", brewName: "ripgrep", category: .search),
        ToolRecipe(name: "fd", description: "Simple, fast alternative to find", brewName: "fd", category: .search),
        ToolRecipe(name: "fzf", description: "Fuzzy finder — interactive filtering for any list", brewName: "fzf", category: .search),
        ToolRecipe(name: "tree", description: "Display directory structure as a tree", brewName: "tree", category: .search),
        ToolRecipe(name: "zoxide", description: "Smarter cd that learns your most-used directories", brewName: "zoxide", category: .search),

        // Shell Enhancements
        ToolRecipe(name: "bat", description: "Cat clone with syntax highlighting and git integration", brewName: "bat", category: .shell),
        ToolRecipe(name: "eza", description: "Modern replacement for ls with colors and icons", brewName: "eza", category: .shell),
        ToolRecipe(name: "tldr", description: "Simplified, community-driven man pages", brewName: "tldr", category: .shell),
        ToolRecipe(name: "htop", description: "Interactive process viewer (better top)", brewName: "htop", category: .shell),
        ToolRecipe(name: "tmux", description: "Terminal multiplexer — split panes, persistent sessions", brewName: "tmux", category: .shell),
        ToolRecipe(name: "starship", description: "Minimal, fast, customizable shell prompt", brewName: "starship", category: .shell),

        // Developer Tools
        ToolRecipe(name: "xcodegen", description: "Generate Xcode projects from a YAML spec", brewName: "xcodegen", category: .devTools),
        ToolRecipe(name: "swiftlint", description: "Linter and style checker for Swift code", brewName: "swiftlint", category: .devTools),
        ToolRecipe(name: "httpie", description: "User-friendly HTTP client (better curl)", brewName: "httpie", category: .devTools),
        ToolRecipe(name: "wget", description: "Network file downloader", brewName: "wget", category: .devTools),

        // Containers & Cloud
        ToolRecipe(name: "docker", description: "Container runtime for building and shipping apps", brewName: "--cask docker", category: .containers),
        ToolRecipe(name: "wrangler", description: "Cloudflare Workers CLI for edge deployments", brewName: "wrangler", category: .containers),
        ToolRecipe(name: "terraform", description: "Infrastructure as code for cloud resources", brewName: "terraform", category: .containers),

        // Editors
        ToolRecipe(name: "nvim", description: "Neovim — hyperextensible text editor", brewName: "neovim", category: .editors),
        ToolRecipe(name: "micro", description: "Simple, intuitive terminal editor (nano replacement)", brewName: "micro", category: .editors),
    ]
}

// MARK: - ViewModel

@MainActor @Observable
final class CustomToolsViewModel {

    // MARK: - Published State

    var tools: [CustomTool] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isShowingAddSheet: Bool = false
    var operationInProgress: String? = nil

    // MARK: - Tool Definitions

    private struct ToolDefinition {
        let name: String
        let description: String
        let brewName: String?
        let isUserAdded: Bool

        init(name: String, description: String, brewName: String? = nil, isUserAdded: Bool = false) {
            self.name = name
            self.description = description
            self.brewName = brewName
            self.isUserAdded = isUserAdded
        }
    }

    /// Core tools that are always shown — truly universal for macOS developers.
    private static let knownTools: [ToolDefinition] = [
        ToolDefinition(name: "brew", description: "Homebrew package manager"),
        ToolDefinition(name: "git", description: "Git version control", brewName: "git"),
        ToolDefinition(name: "node", description: "Node.js JavaScript runtime", brewName: "node"),
        ToolDefinition(name: "bun", description: "Bun JavaScript runtime", brewName: "bun"),
        ToolDefinition(name: "python3", description: "Python runtime", brewName: "python3"),
        ToolDefinition(name: "ssh-keygen", description: "SSH key generator"),
    ]

    // MARK: - Persistence

    private static let userToolsKey = "customToolNames"
    private static let userToolDescriptionsKey = "customToolDescriptions"
    private static let userToolBrewNamesKey = "customToolBrewNames"

    private func loadUserTools() -> [ToolDefinition] {
        let names = UserDefaults.standard.stringArray(forKey: Self.userToolsKey) ?? []
        let descriptions = UserDefaults.standard.dictionary(forKey: Self.userToolDescriptionsKey) as? [String: String] ?? [:]
        let brewNames = UserDefaults.standard.dictionary(forKey: Self.userToolBrewNamesKey) as? [String: String] ?? [:]

        return names.map { name in
            ToolDefinition(
                name: name,
                description: descriptions[name] ?? "User-added tool",
                brewName: brewNames[name],
                isUserAdded: true
            )
        }
    }

    private func saveUserTool(name: String, description: String, brewName: String?) {
        var names = UserDefaults.standard.stringArray(forKey: Self.userToolsKey) ?? []
        var descriptions = UserDefaults.standard.dictionary(forKey: Self.userToolDescriptionsKey) as? [String: String] ?? [:]
        var brewNames = UserDefaults.standard.dictionary(forKey: Self.userToolBrewNamesKey) as? [String: String] ?? [:]

        if !names.contains(name) {
            names.append(name)
        }
        descriptions[name] = description
        if let brewName { brewNames[name] = brewName }

        UserDefaults.standard.set(names, forKey: Self.userToolsKey)
        UserDefaults.standard.set(descriptions, forKey: Self.userToolDescriptionsKey)
        UserDefaults.standard.set(brewNames, forKey: Self.userToolBrewNamesKey)
    }

    private func removeUserTool(name: String) {
        var names = UserDefaults.standard.stringArray(forKey: Self.userToolsKey) ?? []
        var descriptions = UserDefaults.standard.dictionary(forKey: Self.userToolDescriptionsKey) as? [String: String] ?? [:]
        var brewNames = UserDefaults.standard.dictionary(forKey: Self.userToolBrewNamesKey) as? [String: String] ?? [:]

        names.removeAll { $0 == name }
        descriptions.removeValue(forKey: name)
        brewNames.removeValue(forKey: name)

        UserDefaults.standard.set(names, forKey: Self.userToolsKey)
        UserDefaults.standard.set(descriptions, forKey: Self.userToolDescriptionsKey)
        UserDefaults.standard.set(brewNames, forKey: Self.userToolBrewNamesKey)
    }

    // MARK: - Recipes

    /// Recipes that haven't been added yet (filter out built-in + user-added).
    var availableRecipes: [ToolRecipe] {
        let existing = Set(tools.map(\.name))
        return ToolRecipe.catalog.filter { !existing.contains($0.name) }
    }

    // MARK: - Computed

    var filteredTools: [CustomTool] {
        guard !searchText.isEmpty else { return tools }
        return tools.filter { tool in
            tool.name.localizedCaseInsensitiveContains(searchText) ||
            tool.description.localizedCaseInsensitiveContains(searchText) ||
            tool.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var availableTools: [CustomTool] {
        filteredTools.filter(\.isInPATH)
    }

    var unavailableTools: [CustomTool] {
        filteredTools.filter { !$0.isInPATH }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        errorMessage = nil

        Task {
            let allDefinitions = mergedDefinitions()
            var results: [CustomTool] = []

            for definition in allDefinitions {
                let tool = await checkTool(definition)
                results.append(tool)
            }

            sortTools(&results)

            await MainActor.run {
                self.tools = results
                self.isLoading = false
            }
        }
    }

    // MARK: - Refresh

    func refreshAvailability() {
        isLoading = true
        errorMessage = nil

        Task {
            var refreshed: [CustomTool] = []

            for tool in tools {
                let definition = ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    brewName: tool.brewName,
                    isUserAdded: tool.isUserAdded
                )
                let updated = await checkTool(definition)
                refreshed.append(updated)
            }

            sortTools(&refreshed)

            await MainActor.run {
                self.tools = refreshed
                self.isLoading = false
            }
        }
    }

    // MARK: - Add Tool

    func addTool(name: String, description: String, brewName: String? = nil) {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }

        // Don't add duplicates
        guard !tools.contains(where: { $0.name == trimmedName }) else {
            errorMessage = "'\(trimmedName)' is already in the list."
            return
        }

        let desc = description.isEmpty ? "User-added tool" : description

        // Persist with full metadata
        saveUserTool(name: trimmedName, description: desc, brewName: brewName)

        let definition = ToolDefinition(
            name: trimmedName,
            description: desc,
            brewName: brewName,
            isUserAdded: true
        )

        Task {
            let tool = await checkTool(definition)
            await MainActor.run {
                self.tools.append(tool)
                sortTools(&self.tools)
            }
        }
    }

    /// Add a tool from a recipe.
    func addRecipe(_ recipe: ToolRecipe) {
        addTool(name: recipe.name, description: recipe.description, brewName: recipe.brewName)
    }

    // MARK: - Remove Tool

    func removeTool(_ tool: CustomTool) {
        guard tool.isUserAdded else { return }

        tools.removeAll { $0.id == tool.id }
        removeUserTool(name: tool.name)
    }

    // MARK: - Install via Homebrew

    func install(_ tool: CustomTool) {
        guard let brewName = tool.brewName, !brewName.isEmpty else { return }

        operationInProgress = tool.name
        errorMessage = nil

        Task {
            do {
                let command = "brew install \(brewName)"
                let result = try await ProcessService.run(command)
                guard result.succeeded else {
                    await MainActor.run {
                        self.errorMessage = "Install failed: \(result.error)"
                        self.operationInProgress = nil
                    }
                    return
                }

                // Re-check this specific tool
                let definition = ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    brewName: tool.brewName,
                    isUserAdded: tool.isUserAdded
                )
                let updated = await checkTool(definition)

                await MainActor.run {
                    if let index = self.tools.firstIndex(where: { $0.id == tool.id }) {
                        self.tools[index] = updated
                    }
                    sortTools(&self.tools)
                    self.operationInProgress = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Install failed: \(error.localizedDescription)"
                    self.operationInProgress = nil
                }
            }
        }
    }

    // MARK: - Private

    /// Merge built-in definitions with user-added tools.
    private func mergedDefinitions() -> [ToolDefinition] {
        var definitions = Self.knownTools
        let builtInNames = Set(definitions.map(\.name))

        for userTool in loadUserTools() {
            guard !builtInNames.contains(userTool.name) else { continue }
            definitions.append(userTool)
        }

        return definitions
    }

    private func checkTool(_ definition: ToolDefinition) async -> CustomTool {
        do {
            let result = try await ProcessService.run("which \(definition.name)")
            if result.succeeded {
                let path = result.output.trimmed

                // Resolve symlinks to determine true provenance
                let resolvedPath = await resolvePath(path)
                let source = ToolSource.from(path: resolvedPath)

                return CustomTool(
                    name: definition.name,
                    path: path,
                    description: definition.description,
                    isInPATH: true,
                    source: source,
                    brewName: definition.brewName,
                    isUserAdded: definition.isUserAdded
                )
            }
        } catch {
            // Tool lookup failed; treat as not installed
        }

        return CustomTool(
            name: definition.name,
            path: "",
            description: definition.description,
            isInPATH: false,
            source: .unknown,
            brewName: definition.brewName,
            isUserAdded: definition.isUserAdded
        )
    }

    /// Resolve symlinks to find the real path (for provenance detection).
    private func resolvePath(_ path: String) async -> String {
        do {
            let result = try await ProcessService.run("realpath \(path.singleQuoted)")
            if result.succeeded {
                return result.output.trimmed
            }
        } catch {
            // Fall through
        }
        return path
    }

    private func sortTools(_ tools: inout [CustomTool]) {
        tools.sort { lhs, rhs in
            if lhs.isInPATH != rhs.isInPATH {
                return lhs.isInPATH
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Import / Export

    /// Exports user-added tools as JSON.
    func exportData() -> String {
        let userTools = tools.filter(\.isUserAdded)
        let entries: [[String: String]] = userTools.map { tool in
            var entry: [String: String] = [
                "name": tool.name,
                "description": tool.description
            ]
            if let brewName = tool.brewName, !brewName.isEmpty {
                entry["brewName"] = brewName
            }
            return entry
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    func previewImport(_ content: String) -> ImportPreview {
        guard let data = content.data(using: .utf8),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return ImportPreview(
                fileName: "", sectionName: "Custom Tools", isReplace: false,
                newItems: [], updatedItems: [], unchangedCount: 0,
                warnings: ["Could not parse JSON file."]
            )
        }

        let existingNames = Set(tools.map(\.name))
        var newItems: [String] = []
        var unchanged = 0

        for entry in entries {
            guard let name = entry["name"] else { continue }
            if existingNames.contains(name) {
                unchanged += 1
            } else {
                newItems.append(name)
            }
        }

        return ImportPreview(
            fileName: "",
            sectionName: "Custom Tools",
            isReplace: false,
            newItems: newItems,
            updatedItems: [],
            unchangedCount: unchanged,
            warnings: []
        )
    }

    func applyImport(_ content: String) {
        guard let data = content.data(using: .utf8),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            errorMessage = "Failed to parse imported tools JSON."
            return
        }

        let existingNames = Set(tools.map(\.name))

        for entry in entries {
            guard let name = entry["name"], !existingNames.contains(name) else { continue }
            let description = entry["description"] ?? "Imported tool"
            let brewName = entry["brewName"]
            addTool(name: name, description: description, brewName: brewName)
        }
    }
}
