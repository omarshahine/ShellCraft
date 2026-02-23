import SwiftUI

struct SSHConfigView: View {
    @State private var viewModel = SSHConfigViewModel()
    @Environment(AppState.self) private var appState
    @State private var showingAddHostSheet = false
    @State private var editingHost: SSHHost? = nil
    @State private var importPreview: ImportPreview? = nil
    @State private var pendingImportContent: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $viewModel.selectedTab) {
                ForEach(SSHConfigViewModel.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: 250)

            // Content
            Group {
                switch viewModel.selectedTab {
                case .hosts:
                    hostsTab
                case .keys:
                    keysTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Save bar (only for hosts — keys are not editable via this view)
            if viewModel.selectedTab == .hosts {
                SaveBar(
                    hasChanges: viewModel.hasUnsavedChanges,
                    onSave: {
                        viewModel.save()
                        appState.markSaved(.sshConfig)
                    },
                    onDiscard: {
                        viewModel.discard()
                        appState.markSaved(.sshConfig)
                    }
                )
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.selectedTab == .hosts {
                    ImportExportToolbar(
                        onExport: { exportSSH() },
                        onImport: { importSSH() }
                    )
                }

                if viewModel.selectedTab == .hosts {
                    Button {
                        showingAddHostSheet = true
                    } label: {
                        Label("Add Host", systemImage: "plus")
                    }
                    .help("Add a new SSH host entry")
                }

                if viewModel.selectedTab == .keys {
                    Button {
                        viewModel.showingKeyGenerator = true
                    } label: {
                        Label("Generate Key", systemImage: "plus")
                    }
                    .help("Generate a new SSH key pair")
                }

                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload SSH configuration")

                RevealInFinderButton(path: "~/.ssh")
            }
        }
        .navigationTitle("SSH Configuration")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $showingAddHostSheet) {
            SSHHostEditorSheet(
                host: nil,
                onSave: { host in
                    viewModel.addHost(host)
                    appState.markUnsaved(.sshConfig)
                }
            )
        }
        .sheet(item: $editingHost) { host in
            SSHHostEditorSheet(
                host: host,
                onSave: { updatedHost in
                    viewModel.updateHost(updatedHost)
                    appState.markUnsaved(.sshConfig)
                }
            )
        }
        .sheet(isPresented: $viewModel.showingKeyGenerator) {
            SSHKeyGeneratorSheet { type, name, passphrase, comment in
                Task {
                    _ = await viewModel.generateKey(
                        type: type,
                        name: name,
                        passphrase: passphrase,
                        comment: comment
                    )
                }
            }
        }
        .sheet(item: $importPreview) { preview in
            ImportConfirmationSheet(
                preview: preview,
                onConfirm: {
                    if let content = pendingImportContent {
                        viewModel.applyImport(content)
                        appState.markUnsaved(.sshConfig)
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
        .onChange(of: viewModel.hasUnsavedChanges) { _, hasChanges in
            Task { @MainActor in
                if hasChanges {
                    appState.markUnsaved(.sshConfig)
                } else {
                    appState.markSaved(.sshConfig)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var subtitle: String {
        switch viewModel.selectedTab {
        case .hosts:
            "\(viewModel.hosts.count) host\(viewModel.hosts.count == 1 ? "" : "s")"
        case .keys:
            "\(viewModel.keys.count) key\(viewModel.keys.count == 1 ? "" : "s")"
        }
    }

    // MARK: - Import / Export

    private func exportSSH() {
        let content = viewModel.exportData()
        let fileType = ExportFileType(
            defaultName: "ssh-config.txt",
            allowedContentTypes: [.plainText]
        )
        ImportExportService.export(content: content, fileType: fileType)
    }

    private func importSSH() {
        guard let result = ImportExportService.importFile(
            allowedContentTypes: [.plainText],
            title: "Import SSH Config"
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

    // MARK: - Hosts Tab

    private var hostsTab: some View {
        Group {
            if viewModel.filteredHosts.isEmpty {
                hostsEmptyState
            } else {
                hostsList
            }
        }
    }

    private var hostsList: some View {
        List {
            ForEach(viewModel.filteredHosts) { host in
                SSHHostRow(host: host) {
                    editingHost = host
                } onDelete: {
                    viewModel.deleteHost(host)
                    appState.markUnsaved(.sshConfig)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var hostsEmptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.searchText.isEmpty ? "No SSH Hosts" : "No Results",
                systemImage: viewModel.searchText.isEmpty ? "network" : "magnifyingglass"
            )
        } description: {
            if viewModel.searchText.isEmpty {
                Text("No SSH host configurations found in ~/.ssh/config.\nAdd hosts using the + button above.")
            } else {
                Text("No hosts match \"\(viewModel.searchText)\".")
            }
        } actions: {
            if viewModel.searchText.isEmpty {
                Button("Add Host") {
                    showingAddHostSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Keys Tab

    private var keysTab: some View {
        Group {
            if viewModel.filteredKeys.isEmpty {
                keysEmptyState
            } else {
                keysList
            }
        }
    }

    private var keysList: some View {
        List {
            ForEach(viewModel.filteredKeys) { key in
                SSHKeyRow(key: key) {
                    Task { await viewModel.deleteKey(key) }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var keysEmptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.searchText.isEmpty ? "No SSH Keys" : "No Results",
                systemImage: viewModel.searchText.isEmpty ? "lock.shield" : "magnifyingglass"
            )
        } description: {
            if viewModel.searchText.isEmpty {
                Text("No SSH keys found in ~/.ssh/.\nGenerate a new key using the + button above.")
            } else {
                Text("No keys match \"\(viewModel.searchText)\".")
            }
        } actions: {
            if viewModel.searchText.isEmpty {
                Button("Generate Key") {
                    viewModel.showingKeyGenerator = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - SSH Host Row

private struct SSHHostRow: View {
    let host: SSHHost
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: host.host == "*" ? "globe" : "network")
                .foregroundStyle(host.host == "*" ? .orange : .accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.host)
                    .font(.body.weight(.medium))
                    .fontDesign(.monospaced)

                HStack(spacing: 8) {
                    if !host.hostname.isEmpty {
                        Label(host.hostname, systemImage: "server.rack")
                    }
                    if !host.user.isEmpty {
                        Label(host.user, systemImage: "person")
                    }
                    if let port = host.port {
                        Label("\(port)", systemImage: "number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !host.identityFile.isEmpty {
                Label {
                    Text(URL(fileURLWithPath: host.identityFile.expandingTildeInPath).lastPathComponent)
                } icon: {
                    Image(systemName: "key")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            if !host.options.isEmpty {
                Text("\(host.options.count) opt\(host.options.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit host")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete host")
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete Host",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \"\(host.host)\"", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the host \"\(host.host)\" from your SSH config. Save to apply.")
        }
    }
}

// MARK: - SSH Key Row

private struct SSHKeyRow: View {
    let key: SSHKey
    let onDelete: () -> Void

    @State private var copied = false
    @State private var showDeleteConfirmation = false

    private var filename: String {
        URL(fileURLWithPath: key.path).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(keyColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(filename)
                        .font(.body.weight(.medium))
                        .fontDesign(.monospaced)

                    Text(key.type.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(keyColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(keyColor)
                }

                if !key.fingerprint.isEmpty {
                    Text(key.fingerprint)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            if key.hasPassphrase {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("Protected with passphrase")
            }

            if !key.publicKey.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(key.publicKey, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? "Copied" : "Copy Public Key",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy public key to clipboard")
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete key pair")
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete SSH Key",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \"\(filename)\"", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Both the private key and public key (.pub) will be permanently moved to the Trash.")
        }
    }

    private var keyColor: Color {
        switch key.type {
        case .ed25519: .green
        case .rsa: .blue
        case .ecdsa: .purple
        case .dsa: .orange
        }
    }
}
