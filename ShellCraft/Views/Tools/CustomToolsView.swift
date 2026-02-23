import SwiftUI

struct CustomToolsView: View {
    @State private var viewModel = CustomToolsViewModel()
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.tools.isEmpty {
                ProgressView("Scanning tools...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.tools.isEmpty {
                ContentUnavailableView(
                    "No Tools Found",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Could not scan for developer tools.")
                )
            } else {
                toolsList
            }
        }
        .navigationTitle("Custom Tools")
        .searchable(text: $viewModel.searchText, placement: .toolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportTools() },
                    onImport: { importTools() }
                )

                Button {
                    viewModel.isShowingAddSheet = true
                } label: {
                    Label("Add Tool", systemImage: "plus")
                }

                Button {
                    viewModel.refreshAvailability()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $viewModel.isShowingAddSheet) {
            AddToolSheet(viewModel: viewModel)
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
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .onAppear {
            if viewModel.tools.isEmpty {
                viewModel.load()
            }
        }
    }

    // MARK: - Import / Export

    private func exportTools() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "custom-tools.json",
            allowedContentTypes: [.json]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importTools() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.json],
            title: "Import Custom Tools"
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

    // MARK: - Tools List

    @ViewBuilder
    private var toolsList: some View {
        List {
            if !viewModel.availableTools.isEmpty {
                Section("Available") {
                    ForEach(viewModel.availableTools) { tool in
                        toolRow(tool)
                    }
                }
            }

            if !viewModel.unavailableTools.isEmpty {
                Section("Not Installed") {
                    ForEach(viewModel.unavailableTools) { tool in
                        toolRow(tool)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Tool Row

    @ViewBuilder
    private func toolRow(_ tool: CustomTool) -> some View {
        HStack(spacing: 10) {
            StatusBadge(status: tool.isInPATH ? .valid : .invalid)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(.body.monospaced())
                        .fontWeight(.medium)

                    if tool.isInPATH {
                        sourceBadge(for: tool.source)
                    }

                    if tool.isUserAdded {
                        Text("custom")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if tool.isInPATH {
                Text(tool.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else if viewModel.operationInProgress == tool.name {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80)
            } else if let brewName = tool.brewName, !brewName.isEmpty {
                Button("Install") {
                    viewModel.install(tool)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if tool.isUserAdded {
                Button("Remove", role: .destructive) {
                    viewModel.removeTool(tool)
                }
            }
        }
    }

    // MARK: - Source Badge

    @ViewBuilder
    private func sourceBadge(for source: ToolSource) -> some View {
        let (label, color): (String, Color) = switch source {
        case .homebrew: ("Homebrew", .blue)
        case .system: ("System", .gray)
        case .userInstalled: ("User", .purple)
        case .unknown: ("Unknown", .gray)
        }

        Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Add Tool Sheet

struct AddToolSheet: View {
    let viewModel: CustomToolsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var isShowingCustomEntry: Bool = false

    private var filteredRecipes: [ToolRecipe] {
        let recipes = viewModel.availableRecipes
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedRecipes: [(ToolRecipe.Category, [ToolRecipe])] {
        let grouped = Dictionary(grouping: filteredRecipes, by: \.category)
        return ToolRecipe.Category.allCases.compactMap { category in
            guard let recipes = grouped[category], !recipes.isEmpty else { return nil }
            return (category, recipes)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupedRecipes.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if groupedRecipes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("All suggested tools have been added!")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedRecipes, id: \.0) { category, recipes in
                            Section(category.rawValue) {
                                ForEach(recipes) { recipe in
                                    recipeRow(recipe)
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search tools...")
            .navigationTitle("Add Tools")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Custom...") {
                        isShowingCustomEntry = true
                    }
                }
            }
        }
        .frame(width: 520, height: 500)
        .sheet(isPresented: $isShowingCustomEntry) {
            CustomToolEntrySheet { name, description in
                viewModel.addTool(name: name, description: description)
            }
        }
    }

    @ViewBuilder
    private func recipeRow(_ recipe: ToolRecipe) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.body.monospaced())
                    .fontWeight(.medium)

                Text(recipe.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if recipe.brewName != nil {
                Text("Homebrew")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            Button("Add") {
                viewModel.addRecipe(recipe)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Custom Tool Entry Sheet

struct CustomToolEntrySheet: View {
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tool name (e.g. htop)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                } footer: {
                    Text("The command name as it appears in your PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Optional description", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: {
                    Text("Description")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Custom Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(name, description)
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 280)
    }
}
