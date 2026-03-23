import SwiftUI
import UniformTypeIdentifiers

/// Main container view for Ghostty terminal configuration.
/// Uses a segmented tab picker for Theme, Appearance, and General settings.
struct GhosttySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GhosttyViewModel()
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        Group {
            if !viewModel.isInstalled {
                ContentUnavailableView(
                    "Ghostty Not Installed",
                    systemImage: "terminal",
                    description: Text("Install Ghostty from ghostty.org to manage its configuration here.")
                )
            } else {
                VStack(spacing: 0) {
                    Picker("View", selection: $viewModel.selectedTab) {
                        ForEach(GhosttyTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Group {
                        switch viewModel.selectedTab {
                        case .theme:
                            GhosttyThemeView(viewModel: viewModel)
                        case .appearance:
                            GhosttyAppearanceView(viewModel: viewModel)
                        case .general:
                            GhosttyGeneralView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    SaveBar(hasChanges: viewModel.hasUnsavedChanges, onSave: {
                        viewModel.save()
                        appState.markSaved(.ghostty)
                    }, onDiscard: {
                        viewModel.discard()
                        appState.markSaved(.ghostty)
                    })
                }
            }
        }
        .navigationTitle("Ghostty")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isInstalled {
                    ImportExportToolbar(
                        onExport: { exportConfig() },
                        onImport: { importConfig() }
                    )
                    RevealInFinderButton(path: "~/.config/ghostty")
                }
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
            prompt: viewModel.selectedTab == .theme ? "Filter themes" : "Search settings"
        )
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
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.hasUnsavedChanges) { _, hasChanges in
            if hasChanges {
                appState.markUnsaved(.ghostty)
            } else {
                appState.markSaved(.ghostty)
            }
        }
    }

    // MARK: - Import/Export

    private func exportConfig() {
        let content = viewModel.exportData()
        ImportExportService.export(
            content: content,
            fileType: ExportFileType(
                defaultName: "ghostty-config",
                allowedContentTypes: [.plainText]
            )
        )
    }

    private func importConfig() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.plainText],
            title: "Import Ghostty Config"
        ) else { return }

        pendingImportContent = result.content
        importPreview = viewModel.previewImport(result.content)
    }
}
