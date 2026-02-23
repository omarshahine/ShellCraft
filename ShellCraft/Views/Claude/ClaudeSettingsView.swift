import SwiftUI

struct ClaudeSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ClaudeSettingsViewModel()
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $viewModel.selectedTab) {
                ForEach(ClaudeTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch viewModel.selectedTab {
                case .general:
                    ClaudeGeneralView(viewModel: viewModel)
                case .permissions:
                    ClaudePermissionsView(viewModel: viewModel.permissionsVM)
                case .hooks:
                    ClaudeHooksView(viewModel: viewModel.hooksVM)
                case .plugins:
                    ClaudePluginsView(viewModel: viewModel.pluginsVM)
                case .mcp:
                    MCPServersView(viewModel: viewModel.mcpServersVM)
                case .env:
                    ClaudeEnvView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SaveBar(hasChanges: viewModel.hasUnsavedChanges, onSave: {
                viewModel.save()
                appState.markSaved(.claudeSettings)
            }, onDiscard: {
                viewModel.discard()
                appState.markSaved(.claudeSettings)
            })
        }
        .navigationTitle("Claude Code Settings")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportSettings() },
                    onImport: { importSettings() }
                )
                RevealInFinderButton(path: "~/.claude")
            }
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
                    appState.markUnsaved(.claudeSettings)
                } else {
                    appState.markSaved(.claudeSettings)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading Claude settings...")
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

    // MARK: - Import / Export

    private func exportSettings() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "claude-settings.json",
            allowedContentTypes: [.json]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importSettings() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.json],
            title: "Import Claude Settings"
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

// MARK: - Environment Variables Sub-View

struct ClaudeEnvView: View {
    @Bindable var viewModel: ClaudeSettingsViewModel

    var body: some View {
        List {
            Section {
                ForEach($viewModel.envVars) { $entry in
                    HStack {
                        TextField("Key", text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 200)

                        Text("=")
                            .foregroundStyle(.tertiary)

                        TextField("Value", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button(role: .destructive) {
                            viewModel.removeEnvVar(entry)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                HStack {
                    Text("Environment Variables")
                    Spacer()
                    Text("\(viewModel.envVars.count) variables")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } footer: {
                Text("Environment variables set in Claude Code's settings.json. These are available to Claude Code sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.addEnvVar()
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
            }
        }
    }
}
