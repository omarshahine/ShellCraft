import SwiftUI

struct PathManagerView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = PathManagerViewModel()
    @State private var showingAddSheet = false
    @State private var newPathText: String = ""
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            pathList

            SaveBar(
                hasChanges: viewModel.hasUnsavedChanges,
                onSave: {
                    viewModel.save()
                    appState.markSaved(.path)
                },
                onDiscard: {
                    viewModel.discard()
                    appState.markSaved(.path)
                }
            )
        }
        .navigationTitle("PATH Manager")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportPath() },
                    onImport: { importPath() }
                )

                if viewModel.isValidating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .help("Validating paths...")
                }

                Button {
                    Task {
                        await viewModel.validatePaths()
                    }
                } label: {
                    Label("Validate", systemImage: "checkmark.shield")
                }
                .help("Validate all paths")

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Path", systemImage: "plus")
                }
                RevealInFinderButton(path: "~/.zshrc")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addPathSheet
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        viewModel.applyImport(content)
                        appState.markUnsaved(.path)
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
                    appState.markUnsaved(.path)
                } else {
                    appState.markSaved(.path)
                }
            }
        }
    }

    // MARK: - Path List

    private var pathList: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading PATH entries...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No PATH Entries",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("No custom PATH entries found in your shell config files.")
                )
            } else {
                List {
                    ForEach(viewModel.entries) { entry in
                        PathEntryRow(entry: entry)
                            .contextMenu {
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.path, forType: .string)
                                }
                                Button("Reveal in Finder") {
                                    let expanded = entry.path.expandingTildeInPath
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
                                }
                                Divider()
                                Button("Remove", role: .destructive) {
                                    viewModel.remove(entry)
                                    appState.markUnsaved(.path)
                                }
                            }
                    }
                    .onMove { source, destination in
                        viewModel.move(from: source, to: destination)
                        appState.markUnsaved(.path)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Add Path Sheet

    private var addPathSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    newPathText = ""
                    showingAddSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Add PATH Entry")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    addPath()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPathText.trimmed.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("/usr/local/bin", text: $newPathText)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .autocorrectionDisabled()
                } header: {
                    Text("Directory Path")
                } footer: {
                    Text("Enter an absolute path or use ~ for home directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !newPathText.trimmed.isEmpty {
                    Section {
                        let expanded = newPathText.trimmed.expandingTildeInPath
                        let exists = FileManager.default.fileExists(atPath: expanded)

                        HStack {
                            StatusBadge(status: exists ? .valid : .invalid)
                            Text(expanded)
                                .fontDesign(.monospaced)
                                .font(.callout)
                            Spacer()
                            Text(exists ? "Directory exists" : "Directory not found")
                                .font(.caption)
                                .foregroundStyle(exists ? .green : .red)
                        }
                    } header: {
                        Text("Expanded Path")
                    }
                }

                Section {
                    Button("Choose Directory...") {
                        chooseDirectory()
                    }
                } footer: {
                    Text("Or use the file picker to browse for a directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 340)
    }

    // MARK: - Actions

    private func addPath() {
        let path = newPathText.trimmed
        guard !path.isEmpty else { return }
        viewModel.add(path: path)
        appState.markUnsaved(.path)
        newPathText = ""
        showingAddSheet = false
    }

    // MARK: - Import / Export

    private func exportPath() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "path.sh",
            allowedContentTypes: [.shellScript, .plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importPath() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.shellScript, .plainText],
            title: "Import PATH"
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

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Choose a directory to add to PATH"

        if panel.runModal() == .OK, let url = panel.url {
            let home = NSHomeDirectory()
            let path = url.path
            if path.hasPrefix(home) {
                newPathText = "~" + path.dropFirst(home.count)
            } else {
                newPathText = path
            }
        }
    }
}
