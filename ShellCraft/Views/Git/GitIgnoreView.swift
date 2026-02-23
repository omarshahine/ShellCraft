import SwiftUI

struct GitIgnoreView: View {
    @Environment(AppState.self) private var appState
    @Binding var content: String
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SourceFileLabel("~/.gitignore_global")
                    Spacer()
                    Text("\(lineCount) lines")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                CodeEditorView(
                    text: $content,
                    language: "gitignore",
                    lineNumbers: true,
                    isEditable: true
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            SaveBar(hasChanges: hasUnsavedChanges, onSave: onSave, onDiscard: onDiscard)
        }
    }

    private var lineCount: Int {
        content.components(separatedBy: "\n").count
    }
}
