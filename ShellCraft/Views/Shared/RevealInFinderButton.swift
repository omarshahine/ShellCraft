import SwiftUI

/// A reusable toolbar button that reveals a file or directory in Finder.
struct RevealInFinderButton: View {
    let path: String

    var body: some View {
        Button {
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
            }
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .help("Open \(path) in Finder")
    }
}
