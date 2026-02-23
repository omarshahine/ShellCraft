import SwiftUI

struct GitConfigView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GitConfigViewModel()
    @State private var showAddSection = false
    @State private var newSectionName = ""
    @State private var newSectionSubsection = ""
    @State private var showAddEntry = false
    @State private var addEntrySection: GitConfigSection?
    @State private var newEntryKey = ""
    @State private var newEntryValue = ""
    @State private var expandedSections: Set<UUID> = []
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            List {
                identitySection
                configSectionsView
            }
            .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search config keys and values")

            SaveBar(hasChanges: viewModel.hasUnsavedChanges, onSave: {
                viewModel.save()
                appState.markSaved(.gitConfig)
            }, onDiscard: {
                viewModel.discard()
                appState.markSaved(.gitConfig)
            })
        }
        .navigationTitle("Git Configuration")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportGitConfig() },
                    onImport: { importGitConfig() }
                )

                Button {
                    showAddSection = true
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
                RevealInFinderButton(path: "~/.gitconfig")
            }
        }
        .sheet(isPresented: $showAddSection) {
            addSectionSheet
        }
        .sheet(isPresented: $showAddEntry) {
            addEntrySheet
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        viewModel.applyImport(content)
                    }
                    importPreview = nil
                    pendingImportContent = nil
                },
                onCancel: {
                    importPreview = nil
                    pendingImportContent = nil
                }
            )
        }
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.hasUnsavedChanges) {
            Task { @MainActor in
                if viewModel.hasUnsavedChanges {
                    appState.markUnsaved(.gitConfig)
                } else {
                    appState.markSaved(.gitConfig)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading Git config...")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Your Name", text: Binding(
                    get: { viewModel.userName },
                    set: { viewModel.userName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            }

            LabeledContent("Email") {
                TextField("your@email.com", text: Binding(
                    get: { viewModel.userEmail },
                    set: { viewModel.userEmail = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            }

            LabeledContent("Default Branch") {
                TextField("main", text: Binding(
                    get: { viewModel.defaultBranch },
                    set: { viewModel.defaultBranch = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            }
        } header: {
            HStack {
                Image(systemName: "person.circle")
                Text("Identity")
            }
        }
    }

    // MARK: - Config Sections

    @ViewBuilder
    private var configSectionsView: some View {
        let sections = viewModel.filteredSections.filter { section in
            // Don't show user/init sections here since they're in the identity section
            !(section.name == "user" && section.subsection == nil) &&
            !(section.name == "init" && section.subsection == nil)
        }

        ForEach(sections) { section in
            Section {
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedSections.contains(section.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedSections.insert(section.id)
                        } else {
                            expandedSections.remove(section.id)
                        }
                    }
                )) {
                    ForEach(section.entries) { entry in
                        entryRow(entry, in: section)
                    }

                    Button {
                        addEntrySection = section
                        newEntryKey = ""
                        newEntryValue = ""
                        showAddEntry = true
                    } label: {
                        Label("Add Entry", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } label: {
                    HStack {
                        Text(section.displayName)
                            .font(.headline)
                            .fontDesign(.monospaced)

                        Spacer()

                        Text("\(section.entries.count) entries")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .contextMenu {
                Button("Add Entry") {
                    addEntrySection = section
                    newEntryKey = ""
                    newEntryValue = ""
                    showAddEntry = true
                }
                Divider()
                Button("Delete Section", role: .destructive) {
                    viewModel.deleteSection(section)
                }
            }
        }
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: GitConfigEntry, in section: GitConfigSection) -> some View {
        HStack {
            Text(entry.key)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 120, alignment: .trailing)

            Text("=")
                .foregroundStyle(.tertiary)

            TextField("value", text: Binding(
                get: { entry.value },
                set: { newValue in
                    viewModel.updateEntry(entry, in: section, value: newValue)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

            Button(role: .destructive) {
                viewModel.deleteEntry(entry, from: section)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help("Delete entry")
        }
    }

    // MARK: - Add Section Sheet

    private var addSectionSheet: some View {
        VStack(spacing: 16) {
            Text("Add Git Config Section")
                .font(.headline)

            Form {
                TextField("Section name (e.g., core, alias)", text: $newSectionName)
                    .textFieldStyle(.roundedBorder)

                TextField("Subsection (optional, e.g., origin)", text: $newSectionSubsection)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            HStack {
                Button("Cancel") {
                    showAddSection = false
                    newSectionName = ""
                    newSectionSubsection = ""
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Add") {
                    let subsection = newSectionSubsection.trimmed.isEmpty ? nil : newSectionSubsection.trimmed
                    viewModel.addSection(name: newSectionName.trimmed, subsection: subsection)
                    showAddSection = false
                    newSectionName = ""
                    newSectionSubsection = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(newSectionName.trimmed.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 400)
    }

    // MARK: - Add Entry Sheet

    private var addEntrySheet: some View {
        VStack(spacing: 16) {
            Text("Add Entry")
                .font(.headline)

            if let section = addEntrySection {
                Text("Section: \(section.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Key", text: $newEntryKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                TextField("Value", text: $newEntryValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            .padding()

            HStack {
                Button("Cancel") {
                    showAddEntry = false
                    newEntryKey = ""
                    newEntryValue = ""
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Add") {
                    if let section = addEntrySection {
                        viewModel.addEntry(to: section, key: newEntryKey.trimmed, value: newEntryValue.trimmed)
                    }
                    showAddEntry = false
                    newEntryKey = ""
                    newEntryValue = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(newEntryKey.trimmed.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 400)
    }

    // MARK: - Import / Export

    private func exportGitConfig() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: ".gitconfig",
            allowedContentTypes: [.plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importGitConfig() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.plainText],
            title: "Import Git Config"
        ) else { return }

        let preview = viewModel.previewImport(result.content)
        pendingImportContent = result.content
        importPreview = ImportPreview(
            fileName: result.fileName,
            sectionName: preview.sectionName,
            isReplace: preview.isReplace,
            newItems: preview.newItems,
            updatedItems: preview.updatedItems,
            unchangedCount: preview.unchangedCount,
            warnings: preview.warnings
        )
    }
}
