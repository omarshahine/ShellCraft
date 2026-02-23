import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView(selection: $appState.selectedSection)
        } detail: {
            if let section = appState.selectedSection {
                detailView(for: section)
            } else {
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose a configuration section from the sidebar.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .aliases:
            ShellAliasesView()
        case .functions:
            ShellFunctionsView()
        case .ohMyZsh:
            OhMyZshView()
        case .path:
            PathManagerView()
        case .envVars:
            EnvVarsView()
        case .secrets:
            SecretsView()
        case .sshConfig:
            SSHConfigView()
        case .gitConfig:
            GitConfigView()
        case .claudeSettings:
            ClaudeSettingsView()
        case .customTools:
            CustomToolsView()
        case .homebrew:
            HomebrewView()
        }
    }
}
