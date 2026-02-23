import SwiftUI

struct SecretRow: View {
    let secret: KeychainSecret
    let isRevealed: Bool
    let revealedValue: String?
    let onToggleReveal: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Key icon
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Key name and account
            VStack(alignment: .leading, spacing: 2) {
                Text(secret.displayKey)
                    .font(.body.weight(.medium))
                    .fontDesign(.monospaced)

                Text(secret.account)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer()

            // Value display
            Group {
                if isRevealed, let value = revealedValue {
                    Text(value)
                        .fontDesign(.monospaced)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                } else {
                    Text(String(repeating: "\u{2022}", count: 12))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)

            // Action buttons
            HStack(spacing: 4) {
                Button {
                    onToggleReveal()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide value" : "Reveal value")

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy value to clipboard")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit secret value")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete secret")
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete Secret",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \"\(secret.displayKey)\"", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the secret \"\(secret.serviceName)\" from the keychain. This action cannot be undone.")
        }
    }
}
