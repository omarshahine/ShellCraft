import SwiftUI

struct SaveBar: View {
    let hasChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        if hasChanges {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                Text("Unsaved Changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Discard", role: .destructive) {
                    onDiscard()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .glassEffect(.regular, in: .rect(cornerRadius: 0))
        }
    }
}
