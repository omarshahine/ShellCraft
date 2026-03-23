import SwiftUI

/// A compact visual preview card for a Ghostty theme.
/// Shows background/foreground colors, ANSI palette, and cursor color.
struct GhosttyThemePreviewCard: View {
    let theme: GhosttyTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // Terminal preview area
                ZStack(alignment: .topLeading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: theme.background ?? "#1a1a1a"))

                    VStack(alignment: .leading, spacing: 6) {
                        // Sample terminal text
                        Text("$ echo \"Hello World\"")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.foreground ?? "#cccccc"))

                        // Cursor preview
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(hex: theme.cursorColor ?? theme.foreground ?? "#ffffff"))
                                .frame(width: 7, height: 12)
                            Text("_")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color(hex: theme.foreground ?? "#cccccc"))
                                .opacity(0.5)
                        }

                        Spacer(minLength: 4)

                        // Palette rows
                        paletteRow(range: 0..<8)
                        paletteRow(range: 8..<16)
                    }
                    .padding(8)
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Theme name
                HStack {
                    Text(theme.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .font(.caption)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func paletteRow(range: Range<Int>) -> some View {
        HStack(spacing: 2) {
            ForEach(range, id: \.self) { index in
                Circle()
                    .fill(Color(hex: theme.paletteHex(index)))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
