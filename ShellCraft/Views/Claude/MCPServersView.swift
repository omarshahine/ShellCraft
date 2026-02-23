import SwiftUI

struct MCPServersView: View {
    @Bindable var viewModel: MCPServersViewModel
    @State private var showAddSheet = false
    @State private var editingServer: MCPServer?
    @State private var expandedServers: Set<UUID> = []

    var body: some View {
        List {
            if viewModel.servers.isEmpty {
                ContentUnavailableView {
                    Label("No MCP Servers", systemImage: "server.rack")
                } description: {
                    Text("No MCP servers configured. Add servers to extend Claude Code with additional capabilities.")
                } actions: {
                    Button("Add Server") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Summary
                Section {
                    HStack(spacing: 16) {
                        Label("\(viewModel.serverCount) Servers", systemImage: "server.rack")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ForEach(MCPServer.Transport.allCases) { transport in
                            let count = viewModel.servers.count { $0.transport == transport }
                            if count > 0 {
                                transportBadge(transport, count: count)
                            }
                        }
                    }
                }

                // Server list
                ForEach(viewModel.servers) { server in
                    serverRow(server)
                        .contextMenu {
                            Button("Edit") {
                                editingServer = server
                            }
                            Button("Copy Name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(server.name, forType: .string)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                viewModel.remove(server)
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MCPServerEditorSheet(mode: .add) { server in
                viewModel.add(server)
            }
        }
        .sheet(item: $editingServer) { server in
            MCPServerEditorSheet(mode: .edit(server)) { updated in
                viewModel.update(updated)
            }
        }
    }

    // MARK: - Server Row

    private func serverRow(_ server: MCPServer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(server.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                Spacer()

                transportBadge(server.transport)
                sourceBadge(server.source)
            }

            // Connection info
            Group {
                switch server.transport {
                case .stdio:
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.caption2)
                        Text(server.command)
                            .lineLimit(1)
                        if !server.args.isEmpty {
                            Text(server.args.joined(separator: " "))
                                .lineLimit(1)
                        }
                    }
                case .http, .sse:
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text(server.url)
                            .lineLimit(1)
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)

            // Environment variables (expandable)
            if !server.env.isEmpty {
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedServers.contains(server.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedServers.insert(server.id)
                        } else {
                            expandedServers.remove(server.id)
                        }
                    }
                )) {
                    ForEach(server.env.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("=")
                                .foregroundStyle(.tertiary)
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } label: {
                    Text("\(server.env.count) environment variable\(server.env.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Transport Badge

    private func transportBadge(_ transport: MCPServer.Transport, count: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(transport.displayName)
                .font(.caption2)
                .fontWeight(.medium)
            if let count {
                Text("\(count)")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(transportColor(transport).opacity(0.15))
        .foregroundStyle(transportColor(transport))
        .clipShape(Capsule())
    }

    private func transportColor(_ transport: MCPServer.Transport) -> Color {
        switch transport {
        case .stdio: .blue
        case .http: .green
        case .sse: .orange
        }
    }

    // MARK: - Source Badge

    private func sourceBadge(_ source: MCPServer.Source) -> some View {
        Text(source == .claudeJson ? ".claude.json" : ".mcp.json")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .foregroundStyle(.tertiary)
            .clipShape(Capsule())
    }
}
