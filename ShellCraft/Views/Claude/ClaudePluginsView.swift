import SwiftUI

struct ClaudePluginsView: View {
    @Bindable var viewModel: ClaudePluginsViewModel

    var body: some View {
        List {
            if viewModel.plugins.isEmpty {
                ContentUnavailableView {
                    Label("No Plugins Found", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("No Claude Code plugins are installed. Install plugins using the Claude Code CLI.")
                }
            } else {
                // Summary
                Section {
                    HStack {
                        summaryBadge(count: viewModel.enabledCount, label: "Enabled", color: .green)
                        summaryBadge(count: viewModel.disabledCount, label: "Disabled", color: .gray)
                        Spacer()
                    }
                }

                // Grouped by marketplace
                ForEach(viewModel.pluginsByMarketplace, id: \.marketplace) { group in
                    Section {
                        ForEach(group.plugins) { plugin in
                            pluginRow(plugin)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundStyle(.secondary)
                            Text(group.marketplace)
                                .font(.headline)
                            Spacer()
                            Text("\(group.plugins.count) plugins")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Plugin Row

    private func pluginRow(_ plugin: ClaudePlugin) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(plugin.enabled ? .medium : .regular)
                    .foregroundStyle(plugin.enabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    if let version = plugin.version {
                        Text("v\(version)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(plugin.qualifiedName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.enabled },
                set: { _ in viewModel.toggle(plugin) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(plugin.enabled ? "Disable" : "Enable") {
                viewModel.toggle(plugin)
            }
            Divider()
            Button("Copy Qualified Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plugin.qualifiedName, forType: .string)
            }
        }
    }

    // MARK: - Summary Badge

    private func summaryBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count) \(label)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }
}
