import SwiftUI

struct ClaudeGeneralView: View {
    @Bindable var viewModel: ClaudeSettingsViewModel

    private let modelOptions = [
        ("", "Default"),
        ("opus", "Opus"),
        ("sonnet", "Sonnet"),
        ("haiku", "Haiku"),
    ]

    private let outputStyleOptions = [
        ("", "Default"),
        ("concise", "Concise"),
        ("verbose", "Verbose"),
        ("Explanatory", "Explanatory"),
        ("markdown", "Markdown"),
    ]

    private let teammateModeOptions = [
        ("auto", "Auto"),
        ("in-process", "In-Process"),
        ("tmux", "tmux"),
    ]

    private let defaultModeOptions = [
        ("default", "Default"),
        ("acceptEdits", "Accept Edits"),
        ("bypassPermissions", "Bypass Permissions"),
    ]

    private let autoUpdatesChannelOptions = [
        ("stable", "Stable"),
        ("latest", "Latest"),
    ]

    var body: some View {
        Form {
            modelAndOutputSection
            behaviorSection
            displaySection
            attributionSection
            maintenanceSection
            securitySection
            sourceSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Model & Output

    @ViewBuilder
    private var modelAndOutputSection: some View {
        Section("Model & Output") {
            Picker("Default Model", selection: Binding(
                get: { viewModel.settings.model ?? "" },
                set: { viewModel.settings.model = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(modelOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)

            Picker("Output Style", selection: Binding(
                get: { viewModel.settings.outputStyle ?? "" },
                set: { viewModel.settings.outputStyle = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(outputStyleOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Language") {
                TextField("Response language", text: Binding(
                    get: { viewModel.settings.language ?? "" },
                    set: { viewModel.settings.language = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            }
        }
    }

    // MARK: - Behavior

    @ViewBuilder
    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Always Enable Extended Thinking", isOn: Binding(
                get: { viewModel.settings.alwaysThinkingEnabled ?? false },
                set: { viewModel.settings.alwaysThinkingEnabled = $0 ? true : nil }
            ))

            Picker("Teammate Mode", selection: Binding(
                get: { viewModel.settings.teammateMode ?? "auto" },
                set: { viewModel.settings.teammateMode = $0 == "auto" ? nil : $0 }
            )) {
                ForEach(teammateModeOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)

            Toggle("Respect .gitignore", isOn: Binding(
                get: { viewModel.settings.respectGitignore ?? true },
                set: { viewModel.settings.respectGitignore = $0 ? nil : false }
            ))

            LabeledContent("Plans Directory") {
                TextField("Plan file location", text: Binding(
                    get: { viewModel.settings.plansDirectory ?? "" },
                    set: { viewModel.settings.plansDirectory = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            }
        }
    }

    // MARK: - Display

    @ViewBuilder
    private var displaySection: some View {
        Section("Display") {
            LabeledContent("Status Line") {
                TextField("Status line text", text: Binding(
                    get: { viewModel.settings.statusLine?.displayText ?? "" },
                    set: { newValue in
                        if newValue.isEmpty {
                            viewModel.settings.statusLine = nil
                        } else if case .config(var config) = viewModel.settings.statusLine {
                            config.command = newValue
                            viewModel.settings.statusLine = .config(config)
                        } else {
                            viewModel.settings.statusLine = .text(newValue)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            }

            Toggle("Show Turn Duration", isOn: Binding(
                get: { viewModel.settings.showTurnDuration ?? true },
                set: { viewModel.settings.showTurnDuration = $0 ? nil : false }
            ))

            Toggle("Terminal Progress Bar", isOn: Binding(
                get: { viewModel.settings.terminalProgressBarEnabled ?? true },
                set: { viewModel.settings.terminalProgressBarEnabled = $0 ? nil : false }
            ))

            Toggle("Spinner Tips", isOn: Binding(
                get: { viewModel.settings.spinnerTipsEnabled ?? true },
                set: { viewModel.settings.spinnerTipsEnabled = $0 ? nil : false }
            ))

            Toggle("Prefers Reduced Motion", isOn: Binding(
                get: { viewModel.settings.prefersReducedMotion ?? false },
                set: { viewModel.settings.prefersReducedMotion = $0 ? true : nil }
            ))
        }
    }

    // MARK: - Attribution

    @ViewBuilder
    private var attributionSection: some View {
        Section {
            LabeledContent("Commit") {
                TextField("Commit attribution", text: Binding(
                    get: { viewModel.settings.attribution?.commitText ?? "" },
                    set: { newValue in
                        updateAttribution(
                            commit: newValue,
                            pr: viewModel.settings.attribution?.prText ?? ""
                        )
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            }

            LabeledContent("Pull Request") {
                TextField("PR attribution", text: Binding(
                    get: { viewModel.settings.attribution?.prText ?? "" },
                    set: { newValue in
                        updateAttribution(
                            commit: viewModel.settings.attribution?.commitText ?? "",
                            pr: newValue
                        )
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            }

            Text("Text appended to commits and PR descriptions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Attribution")
        }
    }

    private func updateAttribution(commit: String, pr: String) {
        if commit.isEmpty && pr.isEmpty {
            viewModel.settings.attribution = nil
        } else {
            viewModel.settings.attribution = .config(
                AttributionValue.AttributionConfig(
                    commit: commit.isEmpty ? nil : commit,
                    pr: pr.isEmpty ? nil : pr
                )
            )
        }
    }

    // MARK: - Maintenance

    @ViewBuilder
    private var maintenanceSection: some View {
        Section("Maintenance") {
            Picker("Auto-Updates Channel", selection: Binding(
                get: { viewModel.settings.autoUpdatesChannel ?? "latest" },
                set: { viewModel.settings.autoUpdatesChannel = $0 == "latest" ? nil : $0 }
            )) {
                ForEach(autoUpdatesChannelOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Cleanup Period (Days)") {
                TextField("30", text: Binding(
                    get: {
                        if let days = viewModel.settings.cleanupPeriodDays {
                            return "\(days)"
                        }
                        return ""
                    },
                    set: { newValue in
                        if let days = Int(newValue) {
                            viewModel.settings.cleanupPeriodDays = days
                        } else if newValue.isEmpty {
                            viewModel.settings.cleanupPeriodDays = nil
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
            }
        }
    }

    // MARK: - Security

    @ViewBuilder
    private var securitySection: some View {
        Section {
            Picker("Default Permission Mode", selection: Binding(
                get: { viewModel.permissionsVM.defaultMode ?? "default" },
                set: { viewModel.permissionsVM.defaultMode = $0 == "default" ? nil : $0 }
            )) {
                ForEach(defaultModeOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)

            Toggle("Skip Dangerous Mode Permission Prompt", isOn: Binding(
                get: { viewModel.settings.skipDangerousModePermissionPrompt ?? false },
                set: { viewModel.settings.skipDangerousModePermissionPrompt = $0 ? true : nil }
            ))

            Toggle("Disable All Hooks", isOn: Binding(
                get: { viewModel.settings.disableAllHooks ?? false },
                set: { viewModel.settings.disableAllHooks = $0 ? true : nil }
            ))

            Text("Sandbox and other complex settings are preserved but not editable here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Security")
        }
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            SourceFileLabel("~/.claude/settings.json")
        }
    }
}
