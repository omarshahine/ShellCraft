import SwiftUI

/// Theme browser tab with a searchable grid of visual theme previews.
struct GhosttyThemeView: View {
    @Bindable var viewModel: GhosttyViewModel

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 250))]

    var body: some View {
        VStack(spacing: 0) {
            // Current theme header
            if let currentName = selectedThemeName,
               let currentTheme = viewModel.parsedThemes[currentName] {
                HStack(spacing: 12) {
                    // Mini preview of current theme
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: currentTheme.background ?? "#1a1a1a"))
                        Text("Aa")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: currentTheme.foreground ?? "#cccccc"))
                    }
                    .frame(width: 36, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Current Theme")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentName)
                            .font(.headline)
                    }

                    Spacer()

                    // Light/dark auto-switch toggle
                    Toggle("Auto light/dark", isOn: $viewModel.useAutoTheme)
                        .toggleStyle(.switch)
                        .fixedSize()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Light/dark pickers (only when auto-theme is on)
                if viewModel.useAutoTheme {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Light")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Light", selection: $viewModel.lightTheme) {
                                Text("Select...").tag("")
                                ForEach(viewModel.themeNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Dark", selection: $viewModel.darkTheme) {
                                Text("Select...").tag("")
                                ForEach(viewModel.themeNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                Divider()
            }

            // Theme grid
            if viewModel.isLoadingThemes {
                VStack {
                    Spacer()
                    ProgressView("Loading themes...")
                    Spacer()
                }
            } else if viewModel.filteredThemeNames.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.filteredThemeNames, id: \.self) { name in
                                if let theme = viewModel.parsedThemes[name] {
                                    let isSelected = isThemeSelected(name)
                                    GhosttyThemePreviewCard(
                                        theme: theme,
                                        isSelected: isSelected,
                                        onSelect: { viewModel.setTheme(name) }
                                    )
                                    .id(name)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.isLoadingThemes) { _, isLoading in
                        if !isLoading {
                            scrollToSelected(proxy: proxy)
                        }
                    }
                }
            }
        }
        .task {
            if viewModel.parsedThemes.isEmpty {
                await viewModel.loadThemes()
            }
        }
    }

    /// The currently selected theme name (handles both single and auto-theme modes).
    private var selectedThemeName: String? {
        let raw = viewModel.currentThemeRaw
        guard !raw.isEmpty else { return nil }
        if viewModel.useAutoTheme {
            return viewModel.darkTheme.isEmpty ? nil : viewModel.darkTheme
        }
        return raw
    }

    private func scrollToSelected(proxy: ScrollViewProxy) {
        guard let selected = selectedThemeName, !selected.isEmpty else { return }
        withAnimation {
            proxy.scrollTo(selected, anchor: .center)
        }
    }

    private func isThemeSelected(_ name: String) -> Bool {
        if viewModel.useAutoTheme {
            return name == viewModel.lightTheme || name == viewModel.darkTheme
        }
        return name == viewModel.currentThemeRaw
    }
}
