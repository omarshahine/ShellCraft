import SwiftUI
import UniformTypeIdentifiers

struct SecretsView: View {
    @State private var viewModel = SecretsViewModel()
    @Environment(AppState.self) private var appState
    @State private var showingAddSheet = false
    @State private var editingSecret: KeychainSecret? = nil
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    // Encrypted import/export state
    @State private var showingPasswordForExport = false
    @State private var showingEncryptedImport = false
    @State private var encryptedImportData: Data? = nil
    @State private var encryptedImportFileName: String = ""
    @State private var showingSetupScript = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.secrets.isEmpty {
                ProgressView("Loading secrets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredSecrets.isEmpty {
                emptyState
            } else {
                secretsList
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Filter secrets")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                importExportMenu

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Secret", systemImage: "plus")
                }
                .help("Add a new keychain secret")

                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh secrets from keychain")
            }
        }
        .navigationTitle("Keychain Secrets")
        .navigationSubtitle("\(viewModel.secrets.count) secret\(viewModel.secrets.count == 1 ? "" : "s") (env/*)")
        .sheet(isPresented: $showingAddSheet) {
            SecretEditorSheet(
                secret: nil,
                onSave: { key, value, account in
                    Task {
                        await viewModel.add(key: key, value: value, account: account)
                    }
                }
            )
        }
        .sheet(item: $editingSecret) { secret in
            SecretEditorSheet(
                secret: secret,
                onSave: { _, value, _ in
                    Task {
                        await viewModel.update(secret, newValue: value)
                    }
                }
            )
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        Task {
                            await viewModel.applyImport(content)
                        }
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
        .sheet(isPresented: $showingPasswordForExport) {
            PasswordSheet(mode: .encrypt) { password in
                Task { await exportEncrypted(password: password) }
            }
        }
        .sheet(isPresented: $showingEncryptedImport) {
            if let data = encryptedImportData {
                EncryptedImportSheet(
                    encryptedData: data,
                    fileName: encryptedImportFileName,
                    viewModel: viewModel
                )
            }
        }
        .sheet(isPresented: $showingSetupScript) {
            SetupScriptSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Import / Export Menu

    private var importExportMenu: some View {
        Menu {
            Section("Schema (Key Names Only)") {
                Button {
                    exportSecrets()
                } label: {
                    Label("Export Schema...", systemImage: "square.and.arrow.up")
                }

                Button {
                    importSecrets()
                } label: {
                    Label("Import Schema...", systemImage: "square.and.arrow.down")
                }
            }

            Section("Encrypted (With Values)") {
                Button {
                    showingPasswordForExport = true
                } label: {
                    Label("Export Encrypted...", systemImage: "lock.shield")
                }

                Button {
                    importEncrypted()
                } label: {
                    Label("Import Encrypted...", systemImage: "lock.open")
                }
            }

            Divider()

            Button {
                showingSetupScript = true
            } label: {
                Label("Generate Setup Script...", systemImage: "terminal")
            }
        } label: {
            Label("Import/Export", systemImage: "arrow.up.arrow.down.square")
        }
        .menuIndicator(.hidden)
        .help("Import, export, or generate setup scripts")
    }

    // MARK: - Secrets List

    private var secretsList: some View {
        List {
            ForEach(viewModel.filteredSecrets) { secret in
                SecretRow(
                    secret: secret,
                    isRevealed: viewModel.isRevealed(secret),
                    revealedValue: viewModel.revealedValues[secret.id],
                    onToggleReveal: {
                        Task { await viewModel.toggleReveal(secret) }
                    },
                    onCopy: {
                        Task {
                            let value = await viewModel.revealValue(for: secret)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                        }
                    },
                    onEdit: {
                        editingSecret = secret
                    },
                    onDelete: {
                        Task { await viewModel.delete(secret) }
                    }
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Schema Import / Export

    private func exportSecrets() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "secrets.json",
            allowedContentTypes: [.json]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importSecrets() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.json],
            title: "Import Secrets"
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

    // MARK: - Encrypted Import / Export

    private func exportEncrypted(password: String) async {
        do {
            let data = try await viewModel.exportEncryptedData(password: password)
            let fileType = ExportFileType(
                defaultName: "secrets.enc",
                allowedContentTypes: [.data]
            )
            ImportExportService.exportData(data, fileType: fileType)
        } catch {
            viewModel.error = error.localizedDescription
        }
    }

    private func importEncrypted() {
        guard let result = ImportExportService.importFileData(
            allowedContentTypes: [.data],
            title: "Import Encrypted Secrets"
        ) else { return }

        encryptedImportData = result.data
        encryptedImportFileName = result.fileName
        showingEncryptedImport = true
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.searchText.isEmpty ? "No Secrets" : "No Results",
                systemImage: viewModel.searchText.isEmpty ? "key.fill" : "magnifyingglass"
            )
        } description: {
            if viewModel.searchText.isEmpty {
                Text("No keychain secrets with the env/ prefix were found.\nAdd secrets using the + button above.")
            } else {
                Text("No secrets match \"\(viewModel.searchText)\".")
            }
        } actions: {
            if viewModel.searchText.isEmpty {
                Button("Add Secret") {
                    showingAddSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
