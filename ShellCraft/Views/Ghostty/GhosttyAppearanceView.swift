import SwiftUI
import AppKit

/// Appearance settings tab: font, cursor, window, and opacity controls.
struct GhosttyAppearanceView: View {
    @Bindable var viewModel: GhosttyViewModel
    @State private var fontSearch = ""
    @State private var showAllFonts = false

    /// Popular coding fonts, checked against what's actually installed.
    private static let recommendedFamilies: [String] = [
        // Premium
        "Berkeley Mono", "Berkeley Mono Variable",
        "MonoLisa", "MonoLisa Variable",
        "Dank Mono",
        "Operator Mono",
        "PragmataPro", "PragmataPro Liga",
        "Cartograph CF",
        // Free heavy-hitters
        "JetBrains Mono", "JetBrains Mono NL",
        "Cascadia Code", "Cascadia Mono",
        "Fira Code",
        "IBM Plex Mono",
        "Source Code Pro",
        "SF Mono",
        // Modern free
        "Monaspace Neon", "Monaspace Argon", "Monaspace Xenon", "Monaspace Radon", "Monaspace Krypton",
        "Geist Mono",
        "Commit Mono",
        "Iosevka", "Iosevka Term",
        "Recursive Mono Linear", "Recursive Mono Casual",
        "Intel One Mono",
        "0xProto",
        "Maple Mono", "Maple Mono NF",
        // Classics
        "Hack",
        "Inconsolata",
        "Anonymous Pro",
        "Ubuntu Mono",
        "Fira Mono",
        "Roboto Mono",
        "Space Mono",
        "Victor Mono",
        "Fantasque Sans Mono",
        "Comic Mono",
        "Menlo",
        "Monaco",
        "Courier New",
    ]

    /// All monospace fonts on the system.
    private var allMonospaceFonts: [String] {
        let fm = NSFontManager.shared
        return fm.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.isFixedPitch || fm.traits(of: font).contains(.fixedPitchFontMask)
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Recommended fonts that are actually installed.
    private var installedRecommended: [String] {
        let installed = Set(allMonospaceFonts)
        return Self.recommendedFamilies.filter { installed.contains($0) }
    }

    /// All other monospace fonts not in the recommended list.
    private var otherFonts: [String] {
        let recommended = Set(Self.recommendedFamilies)
        return allMonospaceFonts.filter { !recommended.contains($0) }
    }

    /// Whether the current font is not in the recommended list (so we always show it).
    private var currentFontIsOther: Bool {
        let family = viewModel.fontFamily
        guard !family.isEmpty else { return false }
        return !Set(Self.recommendedFamilies).contains(family)
    }

    /// Fonts filtered by search text.
    private var searchResults: [String] {
        let query = fontSearch.lowercased()
        return allMonospaceFonts.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        Form {
            Section("Font") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Family")
                        Spacer()
                        Text(viewModel.fontFamily.isEmpty ? "System Default" : viewModel.fontFamily)
                            .font(fontPreviewFont(viewModel.fontFamily))
                            .foregroundStyle(.secondary)
                    }

                    TextField("Filter fonts", text: $fontSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if fontSearch.isEmpty {
                                // Recommended section
                                if !installedRecommended.isEmpty {
                                    sectionHeader("Recommended")
                                    ForEach(installedRecommended, id: \.self) { family in
                                        fontRow(family)
                                    }
                                }

                                // Show current font in "other" if it's not recommended
                                if currentFontIsOther && !showAllFonts {
                                    sectionHeader("Current")
                                    fontRow(viewModel.fontFamily)
                                }

                                // Other fonts
                                if showAllFonts {
                                    sectionHeader("All Other Fonts")
                                    ForEach(otherFonts, id: \.self) { family in
                                        fontRow(family)
                                    }
                                } else {
                                    Button {
                                        withAnimation { showAllFonts = true }
                                    } label: {
                                        HStack {
                                            Image(systemName: "ellipsis.circle")
                                            Text("Show all \(otherFonts.count) other fonts")
                                        }
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                // Search mode: flat filtered list
                                ForEach(searchResults, id: \.self) { family in
                                    fontRow(family)
                                }
                                if searchResults.isEmpty {
                                    Text("No matching fonts")
                                        .foregroundStyle(.tertiary)
                                        .padding(8)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                    // Live preview
                    Text("The quick brown fox jumps over the lazy dog 0O1lI")
                        .font(.custom(viewModel.fontFamily, size: CGFloat(viewModel.fontSize)))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Stepper("Font Size: \(viewModel.fontSize)", value: $viewModel.fontSize, in: 8...72)
            }

            Section("Cursor") {
                Picker("Style", selection: $viewModel.cursorStyle) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }

                Toggle("Cursor Blink", isOn: $viewModel.cursorBlink)
            }

            Section("Window") {
                HStack {
                    Text("Background Opacity")
                    Spacer()
                    Text(String(format: "%.0f%%", viewModel.backgroundOpacity * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $viewModel.backgroundOpacity, in: 0...1, step: 0.05)

                Stepper("Background Blur: \(viewModel.backgroundBlur)", value: $viewModel.backgroundBlur, in: 0...100)

                Stepper("Padding X: \(viewModel.windowPaddingX)", value: $viewModel.windowPaddingX, in: 0...100)

                Stepper("Padding Y: \(viewModel.windowPaddingY)", value: $viewModel.windowPaddingY, in: 0...100)

                Picker("Window Theme", selection: $viewModel.windowTheme) {
                    Text("Auto").tag("auto")
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("Ghostty").tag("ghostty")
                }

                Picker("Titlebar Style", selection: $viewModel.macosTitlebarStyle) {
                    Text("Native").tag("native")
                    Text("Transparent").tag("transparent")
                    Text("Tabs").tag("tabs")
                    Text("Hidden").tag("hidden")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .padding(.horizontal, 6)
    }

    private func fontRow(_ family: String) -> some View {
        Button {
            viewModel.fontFamily = family
        } label: {
            HStack {
                Text(family)
                    .font(fontPreviewFont(family))
                Spacer()
                if viewModel.fontFamily == family {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                viewModel.fontFamily == family
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func fontPreviewFont(_ family: String) -> Font {
        guard !family.isEmpty else { return .system(.body, design: .monospaced) }
        return .custom(family, size: 13)
    }
}
