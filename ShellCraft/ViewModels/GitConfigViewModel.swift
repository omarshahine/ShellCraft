import Foundation

@MainActor @Observable
final class GitConfigViewModel {

    // MARK: - Properties

    var config = GitConfig()
    var ignoreContent = ""
    var hasUnsavedChanges = false
    var error: String?
    var isLoading = false
    var searchText = ""

    // MARK: - File Paths

    private let configPath = "~/.gitconfig"
    private let ignorePath: String = {
        // Try to resolve core.excludesFile, fall back to ~/.gitignore_global
        "~/.gitignore_global"
    }()

    // MARK: - Snapshots for change tracking

    private var originalConfig = GitConfig()
    private var originalIgnoreContent = ""

    // MARK: - Convenience Properties

    var userName: String {
        get { config.value(section: "user", key: "name") ?? "" }
        set {
            config.setValue(section: "user", key: "name", value: newValue)
            trackChanges()
        }
    }

    var userEmail: String {
        get { config.value(section: "user", key: "email") ?? "" }
        set {
            config.setValue(section: "user", key: "email", value: newValue)
            trackChanges()
        }
    }

    var defaultBranch: String {
        get { config.value(section: "init", key: "defaultBranch") ?? "main" }
        set {
            config.setValue(section: "init", key: "defaultBranch", value: newValue)
            trackChanges()
        }
    }

    /// Sections filtered by search text
    var filteredSections: [GitConfigSection] {
        guard !searchText.isEmpty else { return config.sections }
        let query = searchText.lowercased()
        return config.sections.filter { section in
            section.displayName.lowercased().contains(query) ||
            section.entries.contains { entry in
                entry.key.lowercased().contains(query) ||
                entry.value.lowercased().contains(query)
            }
        }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        error = nil

        do {
            if FileIOService.fileExists(at: configPath) {
                config = try GitConfigService.parse(path: configPath)
            } else {
                config = GitConfig()
            }
            originalConfig = config

            if FileIOService.fileExists(at: ignorePath) {
                ignoreContent = try FileIOService.readFile(at: ignorePath)
            } else {
                ignoreContent = ""
            }
            originalIgnoreContent = ignoreContent

            hasUnsavedChanges = false
        } catch {
            self.error = "Failed to load Git config: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Save

    func save() {
        error = nil

        do {
            try GitConfigService.write(config: config, path: configPath)
            originalConfig = config

            try FileIOService.writeFile(at: ignorePath, content: ignoreContent)
            originalIgnoreContent = ignoreContent

            hasUnsavedChanges = false
        } catch {
            self.error = "Failed to save Git config: \(error.localizedDescription)"
        }
    }

    // MARK: - Discard

    func discard() {
        config = originalConfig
        ignoreContent = originalIgnoreContent
        hasUnsavedChanges = false
    }

    // MARK: - Section Operations

    func addSection(name: String, subsection: String? = nil) {
        let section = GitConfigSection(name: name, subsection: subsection)
        config.sections.append(section)
        trackChanges()
    }

    func deleteSection(_ section: GitConfigSection) {
        config.sections.removeAll { $0.id == section.id }
        trackChanges()
    }

    // MARK: - Entry Operations

    func addEntry(to section: GitConfigSection, key: String, value: String) {
        guard let index = config.sections.firstIndex(where: { $0.id == section.id }) else { return }
        config.sections[index].entries.append(GitConfigEntry(key: key, value: value))
        trackChanges()
    }

    func updateEntry(_ entry: GitConfigEntry, in section: GitConfigSection, value: String) {
        guard let sectionIndex = config.sections.firstIndex(where: { $0.id == section.id }),
              let entryIndex = config.sections[sectionIndex].entries.firstIndex(where: { $0.id == entry.id })
        else { return }
        config.sections[sectionIndex].entries[entryIndex].value = value
        trackChanges()
    }

    func deleteEntry(_ entry: GitConfigEntry, from section: GitConfigSection) {
        guard let sectionIndex = config.sections.firstIndex(where: { $0.id == section.id }) else { return }
        config.sections[sectionIndex].entries.removeAll { $0.id == entry.id }
        trackChanges()
    }

    // MARK: - Change Tracking

    func trackChanges() {
        hasUnsavedChanges = config != originalConfig || ignoreContent != originalIgnoreContent
    }

    // MARK: - Import / Export

    func exportData() -> String {
        GitConfigService.serialize(config: config)
    }

    func previewImport(_ content: String) -> ImportPreview {
        ImportPreview(
            fileName: "",
            sectionName: "Git Configuration",
            isReplace: true,
            newItems: [],
            updatedItems: [],
            unchangedCount: 0,
            warnings: ["This will replace your current Git configuration."]
        )
    }

    func applyImport(_ content: String) {
        config = GitConfigService.parse(content: content)
        trackChanges()
    }
}
