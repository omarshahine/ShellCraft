import SwiftUI

struct HomebrewView: View {
    @State private var viewModel = HomebrewViewModel()
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportURL: URL? = nil

    var body: some View {
        Group {
            if !viewModel.isBrewAvailable && !viewModel.isLoading {
                brewNotInstalledView
            } else if viewModel.isLoading && viewModel.packages.isEmpty {
                ProgressView("Loading Homebrew packages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                packageListView
            }
        }
        .navigationTitle("Homebrew")
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search packages...")
        .onSubmit(of: .search) {
            viewModel.search()
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            if newValue.isEmpty {
                viewModel.searchResults = []
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportExportToolbar(
                    onExport: { exportBrewfile() },
                    onImport: { importBrewfile() }
                )

                Button {
                    viewModel.load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)

                RevealInFinderButton(path: "/opt/homebrew")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .alert("Import Brewfile", isPresented: .init(
            get: { pendingImportURL != nil },
            set: { if !$0 { pendingImportURL = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
            Button("Import") {
                if let url = pendingImportURL {
                    viewModel.importBrewfile(at: url)
                }
                pendingImportURL = nil
            }
        } message: {
            Text("This will run `brew bundle install` with the selected Brewfile. New packages will be installed.")
        }
        .alert("Uninstall Package", isPresented: .init(
            get: { viewModel.packagePendingUninstall != nil },
            set: { if !$0 { viewModel.cancelUninstall() } }
        )) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelUninstall()
            }
            Button("Uninstall", role: .destructive) {
                if let package = viewModel.packagePendingUninstall {
                    viewModel.uninstall(package)
                }
            }
        } message: {
            if let package = viewModel.packagePendingUninstall {
                Text("Are you sure you want to uninstall \(package.name)? This cannot be undone.")
            }
        }
        .onAppear {
            if viewModel.packages.isEmpty {
                viewModel.load()
            }
        }
    }

    // MARK: - Import / Export

    private func exportBrewfile() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "Brewfile",
            allowedContentTypes: [.plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importBrewfile() {
        guard let url = ImportExportService.importFileURL(
            allowedContentTypes: [.plainText],
            title: "Import Brewfile"
        ) else { return }
        pendingImportURL = url
    }

    // MARK: - Brew Not Installed

    @ViewBuilder
    private var brewNotInstalledView: some View {
        ContentUnavailableView {
            Label("Homebrew Not Installed", systemImage: "mug")
        } description: {
            Text("Homebrew is required to manage packages. Visit brew.sh to install.")
        } actions: {
            Link("Install Homebrew", destination: URL(string: "https://brew.sh")!)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Package List

    @ViewBuilder
    private var packageListView: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            // Package list
            if viewModel.isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredPackages.isEmpty {
                if !viewModel.searchText.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    ContentUnavailableView(
                        "No Packages",
                        systemImage: "shippingbox",
                        description: Text("No packages match the current filter.")
                    )
                }
            } else {
                List {
                    ForEach(viewModel.filteredPackages) { package in
                        packageRow(package)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        HStack {
            Picker("Filter", selection: $viewModel.filter) {
                ForEach(HomebrewViewModel.PackageFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(viewModel.filteredPackages.count) packages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    // MARK: - Package Row

    @ViewBuilder
    private func packageRow(_ package: HomebrewPackage) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body.monospaced())
                        .fontWeight(.medium)

                    typeBadge(for: package)

                    if package.isInstalled {
                        Text("installed")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if !package.version.isEmpty {
                Text(package.version)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            // Install/Uninstall button
            if viewModel.operationInProgress == package.name {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80)
            } else if package.isInstalled {
                Button("Uninstall", role: .destructive) {
                    viewModel.confirmUninstall(package)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Install") {
                    viewModel.install(package)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Type Badge

    @ViewBuilder
    private func typeBadge(for package: HomebrewPackage) -> some View {
        Text(package.isFormula ? "formula" : "cask")
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(package.isFormula ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
            .foregroundStyle(package.isFormula ? .blue : .purple)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
