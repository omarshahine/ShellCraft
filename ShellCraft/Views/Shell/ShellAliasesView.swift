import SwiftUI

struct ShellAliasesView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ShellAliasesViewModel()
    @State private var showingAddSheet = false
    @State private var editingAlias: ShellAlias? = nil
    @State private var selectedAliasID: ShellAlias.ID? = nil
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            aliasTable

            SaveBar(
                hasChanges: viewModel.hasUnsavedChanges,
                onSave: {
                    viewModel.save()
                    appState.markSaved(.aliases)
                },
                onDiscard: {
                    viewModel.discard()
                    appState.markSaved(.aliases)
                }
            )
        }
        .navigationTitle("Shell Aliases")
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Filter aliases")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportAliases() },
                    onImport: { importAliases() }
                )
                categoryFilterMenu
                addButton
                RevealInFinderButton(path: "~/.zshrc")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AliasEditorSheet(alias: nil) { name, expansion, category, isEnabled in
                viewModel.add(name: name, expansion: expansion)
                appState.markUnsaved(.aliases)
            }
        }
        .sheet(item: $editingAlias) { alias in
            AliasEditorSheet(alias: alias) { name, expansion, category, isEnabled in
                var existing = alias
                existing.name = name
                existing.expansion = expansion
                existing.category = category
                existing.isEnabled = isEnabled
                viewModel.update(existing)
                appState.markUnsaved(.aliases)
            }
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        viewModel.applyImport(content)
                        appState.markUnsaved(.aliases)
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
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.hasUnsavedChanges) { _, hasChanges in
            Task { @MainActor in
                if hasChanges {
                    appState.markUnsaved(.aliases)
                } else {
                    appState.markSaved(.aliases)
                }
            }
        }
    }

    // MARK: - Table

    private var aliasTable: some View {
        Table(viewModel.filteredAliases, selection: $selectedAliasID) {
            TableColumn("Name") { alias in
                HStack(spacing: 6) {
                    if !alias.isEnabled {
                        Image(systemName: "slash.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Text(alias.name)
                        .fontDesign(.monospaced)
                        .foregroundStyle(alias.isEnabled ? .primary : .secondary)
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("Expansion") { alias in
                Text(alias.expansion)
                    .fontDesign(.monospaced)
                    .foregroundStyle(alias.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 200, ideal: 350)

            TableColumn("Category") { alias in
                Text(alias.category.rawValue)
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(categoryColor(alias.category).opacity(0.15))
                    .clipShape(Capsule())
            }
            .width(min: 80, ideal: 100)

            TableColumn("Source") { alias in
                SourceFileLabel(alias.sourceFile, line: alias.lineNumber)
            }
            .width(min: 120, ideal: 160)
        }
        .contextMenu(forSelectionType: ShellAlias.ID.self) { ids in
            if let id = ids.first, let alias = viewModel.aliases.first(where: { $0.id == id }) {
                Button("Edit Alias") {
                    editingAlias = alias
                    // .sheet(item:) triggers automatically
                }
                Button(alias.isEnabled ? "Disable" : "Enable") {
                    viewModel.toggleEnabled(alias)
                    appState.markUnsaved(.aliases)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    viewModel.delete(alias)
                    appState.markUnsaved(.aliases)
                }
            }
        } primaryAction: { ids in
            // Double-click to edit
            if let id = ids.first, let alias = viewModel.aliases.first(where: { $0.id == id }) {
                editingAlias = alias
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading aliases...")
            } else if viewModel.filteredAliases.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.aliases.isEmpty {
                ContentUnavailableView(
                    "No Aliases Found",
                    systemImage: "text.word.spacing",
                    description: Text("No aliases were found in ~/.zshrc or ~/.zprofile.")
                )
            }
        }
    }

    // MARK: - Toolbar Items

    private var categoryFilterMenu: some View {
        Menu {
            Button("All Categories") {
                viewModel.selectedCategory = nil
            }
            Divider()
            ForEach(AliasCategory.allCases) { category in
                Button {
                    viewModel.selectedCategory = category
                } label: {
                    HStack {
                        Text(category.rawValue)
                        if viewModel.selectedCategory == category {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(
                viewModel.selectedCategory?.rawValue ?? "Category",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Add Alias", systemImage: "plus")
        }
    }

    // MARK: - Import / Export

    private func exportAliases() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "aliases.sh",
            allowedContentTypes: [.shellScript, .plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importAliases() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.shellScript, .plainText],
            title: "Import Aliases"
        ) else { return }

        var preview = viewModel.previewImport(result.content)
        preview = ImportPreview(
            fileName: result.fileName,
            sectionName: preview.sectionName,
            isReplace: preview.isReplace,
            newItems: preview.newItems,
            updatedItems: preview.updatedItems,
            unchangedCount: preview.unchangedCount,
            warnings: preview.warnings
        )
        pendingImportContent = result.content
        importPreview = preview
    }

    // MARK: - Helpers

    private func categoryColor(_ category: AliasCategory) -> Color {
        switch category {
        case .git: .blue
        case .navigation: .green
        case .docker: .cyan
        case .system: .orange
        case .network: .purple
        case .general: .gray
        }
    }
}
