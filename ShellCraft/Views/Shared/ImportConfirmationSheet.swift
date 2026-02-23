import SwiftUI

/// Shared confirmation sheet shown before applying an import.
/// Displays a preview of what will change (new items, updated items, warnings).
struct ImportConfirmationSheet: View {
    let preview: ImportPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Import \(preview.sectionName)")
                    .font(.headline)

                Spacer()

                Button("Import") { onConfirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(preview.totalChanges == 0 && !preview.isReplace)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // File info
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(preview.fileName)
                            .font(.callout)
                            .fontDesign(.monospaced)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    // Summary
                    HStack(spacing: 12) {
                        if preview.isReplace {
                            summaryBadge(
                                count: 1,
                                label: "replace",
                                color: .orange,
                                icon: "arrow.triangle.2.circlepath"
                            )
                        } else {
                            if !preview.newItems.isEmpty {
                                summaryBadge(
                                    count: preview.newItems.count,
                                    label: "new",
                                    color: .green,
                                    icon: "plus.circle"
                                )
                            }
                            if !preview.updatedItems.isEmpty {
                                summaryBadge(
                                    count: preview.updatedItems.count,
                                    label: "updated",
                                    color: .blue,
                                    icon: "pencil.circle"
                                )
                            }
                            if preview.unchangedCount > 0 {
                                summaryBadge(
                                    count: preview.unchangedCount,
                                    label: "unchanged",
                                    color: .gray,
                                    icon: "checkmark.circle"
                                )
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Warnings
                    if !preview.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.warnings, id: \.self) { warning in
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Detail lists
                    if !preview.newItems.isEmpty {
                        detailSection(title: "New", items: preview.newItems, color: .green)
                    }
                    if !preview.updatedItems.isEmpty {
                        detailSection(title: "Updated", items: preview.updatedItems, color: .blue)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Components

    private func summaryBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(count) \(label)")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailSection(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal)

            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                    Text(item)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
