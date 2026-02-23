import SwiftUI

/// Reusable toolbar menu providing Export and Import buttons.
/// Add this to any view's `ToolbarItemGroup(placement: .primaryAction)`.
struct ImportExportToolbar: View {
    let onExport: () -> Void
    let onImport: () -> Void

    var body: some View {
        Menu {
            Button {
                onExport()
            } label: {
                Label("Export...", systemImage: "square.and.arrow.up")
            }

            Button {
                onImport()
            } label: {
                Label("Import...", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label("Import/Export", systemImage: "arrow.up.arrow.down.square")
        }
        .menuIndicator(.hidden)
        .help("Import or export configuration")
    }
}
