import SwiftUI

struct MCPServerEditorSheet: View {
    let mode: Mode
    let onSave: (MCPServer) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var transport: MCPServer.Transport
    @State private var url: String
    @State private var command: String
    @State private var argsText: String
    @State private var envEntries: [EnvKV]
    @State private var serverId: UUID

    enum Mode {
        case add
        case edit(MCPServer)

        var title: String {
            switch self {
            case .add: "Add MCP Server"
            case .edit: "Edit MCP Server"
            }
        }

        var isEdit: Bool {
            switch self {
            case .add: false
            case .edit: true
            }
        }
    }

    init(mode: Mode, onSave: @escaping (MCPServer) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _transport = State(initialValue: .stdio)
            _url = State(initialValue: "")
            _command = State(initialValue: "")
            _argsText = State(initialValue: "")
            _envEntries = State(initialValue: [])
            _serverId = State(initialValue: UUID())
        case .edit(let server):
            _name = State(initialValue: server.name)
            _transport = State(initialValue: server.transport)
            _url = State(initialValue: server.url)
            _command = State(initialValue: server.command)
            _argsText = State(initialValue: server.args.joined(separator: "\n"))
            _envEntries = State(initialValue: server.env.map { EnvKV(key: $0.key, value: $0.value) }
                .sorted { $0.key < $1.key })
            _serverId = State(initialValue: server.id)
        }
    }

    private var isValid: Bool {
        guard !name.trimmed.isEmpty else { return false }
        switch transport {
        case .stdio: return !command.trimmed.isEmpty
        case .http, .sse: return !url.trimmed.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(mode.isEdit)

                    Picker("Transport", selection: $transport) {
                        ForEach(MCPServer.Transport.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Transport-specific fields
                switch transport {
                case .stdio:
                    Section("Command") {
                        TextField("Command (e.g., npx, node)", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Arguments (one per line):")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $argsText)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                case .http, .sse:
                    Section("Connection") {
                        TextField("URL (e.g., https://server.example.com/mcp)", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Environment variables
                Section {
                    ForEach($envEntries) { $entry in
                        HStack {
                            TextField("Key", text: $entry.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: 160)

                            Text("=")
                                .foregroundStyle(.tertiary)

                            TextField("Value", text: $entry.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))

                            Button(role: .destructive) {
                                envEntries.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red.opacity(0.6))
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button {
                        envEntries.append(EnvKV(key: "", value: ""))
                    } label: {
                        Label("Add Variable", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Environment Variables")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveServer() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(width: 520, height: 560)
    }

    private func saveServer() {
        let args: [String] = argsText
            .components(separatedBy: "\n")
            .map(\.trimmed)
            .filter { !$0.isEmpty }

        var env: [String: String] = [:]
        for entry in envEntries where !entry.key.trimmed.isEmpty {
            env[entry.key.trimmed] = entry.value
        }

        let server = MCPServer(
            id: serverId,
            name: name.trimmed,
            transport: transport,
            url: url.trimmed,
            command: command.trimmed,
            args: args,
            env: env
        )

        onSave(server)
        dismiss()
    }
}

// MARK: - Key-Value Entry

private struct EnvKV: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}
