import SwiftUI

struct OhMyZshPluginsView: View {
    @Bindable var viewModel: OhMyZshViewModel

    var body: some View {
        List {
            if !viewModel.enabledPlugins.isEmpty {
                Section("Enabled (\(viewModel.enabledPlugins.count))") {
                    ForEach(viewModel.enabledPlugins) { plugin in
                        pluginRow(plugin)
                    }
                }
            }

            Section("Available (\(viewModel.disabledPlugins.count))") {
                ForEach(viewModel.disabledPlugins) { plugin in
                    pluginRow(plugin)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func pluginRow(_ plugin: OhMyZshPlugin) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { plugin.isEnabled },
                set: { _ in viewModel.togglePlugin(plugin) }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.system(.body, design: .monospaced))

                    if plugin.isCustom {
                        Text("custom")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if !plugin.description.isEmpty {
                    Text(plugin.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }
}
