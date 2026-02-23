import SwiftUI

struct PathEntryRow: View {
    let entry: PathEntry

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            // Validity indicator
            StatusBadge(status: entry.exists ? .valid : .invalid)

            // Path info
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.path)
                    .font(.body)
                    .fontDesign(.monospaced)
                    .lineLimit(1)

                if entry.expandedPath != entry.path {
                    Text(entry.expandedPath)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Order badge
            Text("#\(entry.order + 1)")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Source file
            SourceFileLabel(entry.sourceFile)
        }
        .padding(.vertical, 4)
    }
}
