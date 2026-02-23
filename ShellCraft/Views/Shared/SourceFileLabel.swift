import SwiftUI

struct SourceFileLabel: View {
    let path: String
    let lineNumber: Int?

    init(_ path: String, line: Int? = nil) {
        self.path = path
        self.lineNumber = line
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
            if let lineNumber {
                Text("\(displayPath):\(lineNumber)")
            } else {
                Text(displayPath)
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private var displayPath: String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
