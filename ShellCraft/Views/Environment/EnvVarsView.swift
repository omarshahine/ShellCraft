import SwiftUI

struct EnvVarsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = EnvVarsViewModel()
    @State private var showingAddSheet = false
    @State private var editingVariable: EnvironmentVariable? = nil
    @State private var selectedVariableID: EnvironmentVariable.ID? = nil
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            envVarTable

            SaveBar(
                hasChanges: viewModel.hasUnsavedChanges,
                onSave: {
                    viewModel.save()
                    appState.markSaved(.envVars)
                },
                onDiscard: {
                    viewModel.discard()
                    appState.markSaved(.envVars)
                }
            )
        }
        .navigationTitle("Environment Variables")
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Filter variables")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportEnvVars() },
                    onImport: { importEnvVars() }
                )

                if viewModel.keychainVariableCount > 0 {
                    Label(
                        "\(viewModel.keychainVariableCount) keychain",
                        systemImage: "key.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
                RevealInFinderButton(path: "~/.zshrc")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            EnvVarEditorSheet(variable: nil) { key, value, isKeychain in
                viewModel.add(key: key, value: value, isKeychain: isKeychain)
                appState.markUnsaved(.envVars)
            }
        }
        .sheet(item: $editingVariable) { variable in
            EnvVarEditorSheet(variable: variable) { key, value, isKeychain in
                var existing = variable
                existing.key = key
                existing.value = value
                existing.isKeychainDerived = isKeychain
                viewModel.update(existing)
                appState.markUnsaved(.envVars)
            }
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        viewModel.applyImport(content)
                        appState.markUnsaved(.envVars)
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
                    appState.markUnsaved(.envVars)
                } else {
                    appState.markSaved(.envVars)
                }
            }
        }
    }

    // MARK: - Table

    private var envVarTable: some View {
        Table(viewModel.filteredVariables, selection: $selectedVariableID) {
            TableColumn("Key") { variable in
                HStack(spacing: 6) {
                    if variable.isKeychainDerived {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .help("Value derived from macOS Keychain")
                    }
                    Text(variable.key)
                        .fontDesign(.monospaced)
                        .fontWeight(.medium)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("Value") { variable in
                if variable.isKeychainDerived {
                    Text(variable.value)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(variable.value)
                } else {
                    Text(variable.value)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(variable.value)
                }
            }
            .width(min: 200, ideal: 350)

            TableColumn("Source") { variable in
                SourceFileLabel(variable.sourceFile, line: variable.lineNumber)
            }
            .width(min: 120, ideal: 160)
        }
        .contextMenu(forSelectionType: EnvironmentVariable.ID.self) { ids in
            if let id = ids.first, let variable = viewModel.variables.first(where: { $0.id == id }) {
                Button("Edit Variable") {
                    editingVariable = variable
                }
                Button("Copy Value") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(variable.value, forType: .string)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    viewModel.delete(variable)
                    appState.markUnsaved(.envVars)
                }
            }
        } primaryAction: { ids in
            // Double-click to edit
            if let id = ids.first, let variable = viewModel.variables.first(where: { $0.id == id }) {
                editingVariable = variable
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading environment variables...")
            } else if viewModel.filteredVariables.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.variables.isEmpty {
                ContentUnavailableView(
                    "No Environment Variables",
                    systemImage: "list.bullet.rectangle",
                    description: Text("No exported environment variables found in your shell config.")
                )
            }
        }
    }

    // MARK: - Import / Export

    private func exportEnvVars() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "env-vars.sh",
            allowedContentTypes: [.shellScript, .plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importEnvVars() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.shellScript, .plainText],
            title: "Import Environment Variables"
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
