import SwiftUI

struct SSHHostEditorSheet: View {
    /// If non-nil, editing an existing host. Otherwise creating a new one.
    let host: SSHHost?
    let onSave: (SSHHost) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var hostPattern: String
    @State private var hostname: String
    @State private var user: String
    @State private var identityFile: String
    @State private var port: String
    @State private var showAdvanced: Bool
    @State private var advancedOptions: [OptionPair]
    @State private var validationError: String?

    private var isEditing: Bool { host != nil }
    private var title: String { isEditing ? "Edit SSH Host" : "Add SSH Host" }

    private var isValid: Bool {
        !hostPattern.trimmed.isEmpty
    }

    init(host: SSHHost?, onSave: @escaping (SSHHost) -> Void) {
        self.host = host
        self.onSave = onSave
        _hostPattern = State(initialValue: host?.host ?? "")
        _hostname = State(initialValue: host?.hostname ?? "")
        _user = State(initialValue: host?.user ?? "")
        _identityFile = State(initialValue: host?.identityFile ?? "")
        _port = State(initialValue: host?.port.map { String($0) } ?? "")
        let options = host?.options.map { OptionPair(key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key } ?? []
        _advancedOptions = State(initialValue: options)
        _showAdvanced = State(initialValue: !options.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Host Pattern", text: $hostPattern, prompt: Text("e.g., myserver or *.example.com"))
                        .fontDesign(.monospaced)
                        .help("The Host pattern used to match this entry (e.g., myserver, *.example.com)")
                        .onChange(of: hostPattern) { validationError = nil }

                    TextField("HostName", text: $hostname, prompt: Text("e.g., 192.168.1.100 or server.example.com"))
                        .fontDesign(.monospaced)
                        .help("The actual hostname or IP address to connect to")

                    TextField("User", text: $user, prompt: Text("e.g., root or deploy"))
                        .help("The username for the SSH connection")

                    HStack {
                        TextField("IdentityFile", text: $identityFile, prompt: Text("e.g., ~/.ssh/id_ed25519"))
                            .fontDesign(.monospaced)
                            .help("Path to the private key file for authentication")

                        Button("Browse...") {
                            browseForIdentityFile()
                        }
                        .controlSize(.small)
                    }

                    TextField("Port", text: $port, prompt: Text("22"))
                        .help("The SSH port (default: 22)")
                        .onChange(of: port) {
                            // Strip non-numeric characters
                            port = port.filter { $0.isNumber }
                        }
                }

                Section {
                    DisclosureGroup("Advanced Options (\(advancedOptions.count))", isExpanded: $showAdvanced) {
                        ForEach($advancedOptions) { $option in
                            HStack {
                                TextField("Option", text: $option.key)
                                    .fontDesign(.monospaced)
                                    .frame(width: 160)

                                TextField("Value", text: $option.value)
                                    .fontDesign(.monospaced)

                                Button {
                                    advancedOptions.removeAll { $0.id == option.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button {
                            advancedOptions.append(OptionPair())
                        } label: {
                            Label("Add Option", systemImage: "plus")
                        }
                        .controlSize(.small)
                    }
                }

                if let error = validationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    SourceFileLabel("~/.ssh/config")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(width: 520, height: 520)
    }

    // MARK: - Save

    private func save() {
        let trimmedHost = hostPattern.trimmed
        guard !trimmedHost.isEmpty else {
            validationError = "Host pattern is required."
            return
        }

        // Build the options dictionary from the advanced pairs
        var options: [String: String] = [:]
        for pair in advancedOptions where !pair.key.trimmed.isEmpty {
            options[pair.key.trimmed] = pair.value.trimmed
        }

        let parsedPort: Int? = port.isEmpty ? nil : Int(port)

        let result = SSHHost(
            id: host?.id ?? UUID(),
            host: trimmedHost,
            hostname: hostname.trimmed,
            user: user.trimmed,
            identityFile: identityFile.trimmed,
            port: parsedPort,
            options: options
        )

        onSave(result)
        dismiss()
    }

    // MARK: - File Picker

    private func browseForIdentityFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "~/.ssh".expandingTildeInPath)
        panel.message = "Select an SSH private key"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let home = NSHomeDirectory()
            if url.path.hasPrefix(home) {
                identityFile = "~" + url.path.dropFirst(home.count)
            } else {
                identityFile = url.path
            }
        }
    }
}

// MARK: - Option Pair Model

private struct OptionPair: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}
