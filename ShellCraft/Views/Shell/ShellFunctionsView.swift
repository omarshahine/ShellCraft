import SwiftUI

struct ShellFunctionsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ShellFunctionsViewModel()
    @State private var showingAddSheet = false
    @State private var editingFunction: ShellFunction? = nil
    @State private var selectedFunctionID: ShellFunction.ID? = nil
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            functionTable

            SaveBar(
                hasChanges: viewModel.hasUnsavedChanges,
                onSave: {
                    viewModel.save()
                    appState.markSaved(.functions)
                },
                onDiscard: {
                    viewModel.discard()
                    appState.markSaved(.functions)
                }
            )
        }
        .navigationTitle("Shell Functions")
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Filter functions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportFunctions() },
                    onImport: { importFunctions() }
                )
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Function", systemImage: "plus")
                }
                RevealInFinderButton(path: "~/.zshrc")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            FunctionEditorSheet(function: nil) { name, body, description in
                viewModel.add(name: name, body: body, description: description)
                appState.markUnsaved(.functions)
            }
        }
        .sheet(item: $editingFunction) { function in
            FunctionEditorSheet(function: function) { name, body, description in
                var existing = function
                existing.name = name
                existing.body = body
                existing.description = description
                viewModel.update(existing)
                appState.markUnsaved(.functions)
            }
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        viewModel.applyImport(content)
                        appState.markUnsaved(.functions)
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
                    appState.markUnsaved(.functions)
                } else {
                    appState.markSaved(.functions)
                }
            }
        }
    }

    // MARK: - Table

    private var functionTable: some View {
        Table(viewModel.filteredFunctions, selection: $selectedFunctionID) {
            TableColumn("Name") { fn in
                Text(fn.name)
                    .fontDesign(.monospaced)
                    .fontWeight(.medium)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Description") { fn in
                Text(fn.description)
                    .foregroundStyle(fn.description.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Body") { fn in
                Text(fn.body.components(separatedBy: "\n").first ?? "")
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 150, ideal: 300)

            TableColumn("Source") { fn in
                SourceFileLabel(fn.sourceFile, line: fn.lineRange.lowerBound)
            }
            .width(min: 120, ideal: 160)
        }
        .contextMenu(forSelectionType: ShellFunction.ID.self) { ids in
            if let id = ids.first, let fn = viewModel.functions.first(where: { $0.id == id }) {
                Button("Edit Function") {
                    editingFunction = fn
                    // .sheet(item:) triggers automatically
                }
                Divider()
                Button("Delete", role: .destructive) {
                    viewModel.delete(fn)
                    appState.markUnsaved(.functions)
                }
            }
        } primaryAction: { ids in
            // Double-click to edit
            if let id = ids.first, let fn = viewModel.functions.first(where: { $0.id == id }) {
                editingFunction = fn
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading functions...")
            } else if viewModel.filteredFunctions.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.functions.isEmpty {
                ContentUnavailableView(
                    "No Functions Found",
                    systemImage: "function",
                    description: Text("No shell functions were found in your config files.")
                )
            }
        }
    }

    // MARK: - Import / Export

    private func exportFunctions() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "functions.sh",
            allowedContentTypes: [.shellScript, .plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importFunctions() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.shellScript, .plainText],
            title: "Import Functions"
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
