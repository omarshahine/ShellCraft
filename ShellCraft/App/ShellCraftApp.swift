import Sparkle
import SwiftUI

@main
struct ShellCraftApp: App {
    @State private var appState = AppState()

    /// Sparkle's updater. Started at launch so background checks run on the
    /// schedule Sparkle manages; the menu item below only triggers a manual
    /// check. ShellCraft is not sandboxed, so no installer XPC services are
    /// needed and the entitlements file stays empty.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ShellCraft") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: "App icon created by Freepik — Flaticon",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 11),
                                .foregroundColor: NSColor.secondaryLabelColor,
                                .link: URL(string: "https://www.flaticon.com/free-icons/conch")!
                            ]
                        )
                    ])
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
