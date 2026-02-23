import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(group.sections) { section in
                        Label {
                            HStack {
                                Text(section.displayName)
                                Spacer()
                                if appState.hasUnsavedChanges(for: section) {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        } icon: {
                            Image(systemName: section.icon)
                        }
                        .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ShellCraft")
    }
}
