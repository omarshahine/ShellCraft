import SwiftUI
import UniformTypeIdentifiers

struct OhMyZshView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = OhMyZshViewModel()
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isInstalled && !viewModel.isLoading {
                omzNotInstalledView
            } else {
                Picker("View", selection: $viewModel.selectedTab) {
                    ForEach(OhMyZshTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(maxWidth: 300)

                Group {
                    switch viewModel.selectedTab {
                    case .themes:
                        themesTab
                    case .plugins:
                        OhMyZshPluginsView(viewModel: viewModel)
                    case .settings:
                        settingsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                SaveBar(hasChanges: viewModel.hasUnsavedChanges, onSave: {
                    viewModel.save()
                    appState.markSaved(.ohMyZsh)
                }, onDiscard: {
                    viewModel.discard()
                    appState.markSaved(.ohMyZsh)
                })
            }
        }
        .navigationTitle("Oh My Zsh")
        .searchable(text: $viewModel.searchText, placement: .toolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportSettings() },
                    onImport: { importSettings() }
                )

                Button {
                    viewModel.load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload Oh My Zsh configuration")

                RevealInFinderButton(path: "~/.oh-my-zsh")
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
                    appState.markUnsaved(.ohMyZsh)
                } else {
                    appState.markSaved(.ohMyZsh)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading Oh My Zsh...")
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

    // MARK: - Not Installed View

    private var omzNotInstalledView: some View {
        ContentUnavailableView {
            Label("Oh My Zsh Not Installed", systemImage: "terminal")
        } description: {
            Text("Oh My Zsh was not found at ~/.oh-my-zsh/")
        } actions: {
            Link("Install Oh My Zsh",
                 destination: URL(string: "https://ohmyz.sh")!)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Themes Tab

    private var themesTab: some View {
        List {
            let customThemes = viewModel.filteredThemes.filter(\.isCustom)
            let bundledThemes = viewModel.filteredThemes.filter { !$0.isCustom }

            if !customThemes.isEmpty {
                Section("Custom Themes (\(customThemes.count))") {
                    ForEach(customThemes) { theme in
                        themeRow(theme)
                    }
                }
            }

            Section("Bundled Themes (\(bundledThemes.count))") {
                ForEach(bundledThemes) { theme in
                    themeRow(theme)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func themeRow(_ theme: OhMyZshTheme) -> some View {
        let isSelected = viewModel.currentTheme == theme.name
        return Button {
            viewModel.setTheme(theme.name)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                Text(theme.name)
                    .font(.system(.body, design: .monospaced))

                if theme.isCustom {
                    Text("custom")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        List {
            Section {
                ForEach(viewModel.settings) { setting in
                    settingRow(setting)
                }
            } header: {
                Text("Oh My Zsh Settings")
            } footer: {
                Text("These settings are defined in .zshrc before the Oh My Zsh source line. Disabled settings are commented out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func settingRow(_ setting: OhMyZshSetting) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { setting.isEnabled },
                set: { _ in viewModel.toggleSetting(setting) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.key)
                        .font(.system(.body, design: .monospaced))
                    Text(setting.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if setting.isStringValue && setting.isEnabled {
                TextField("Value", text: Binding(
                    get: { setting.value },
                    set: { viewModel.updateSettingValue(setting, value: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - Import / Export

    private func exportSettings() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "oh-my-zsh-config.sh",
            allowedContentTypes: [.shellScript]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importSettings() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.shellScript, .plainText],
            title: "Import Oh My Zsh Config"
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
