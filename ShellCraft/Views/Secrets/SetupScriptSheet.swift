import SwiftUI

/// Three-phase wizard for generating a self-contained setup script:
/// 1. Configure — choose what to include
/// 2. Password — set encryption password
/// 3. Generate — encrypt, build script, save
struct SetupScriptSheet: View {
    let viewModel: SecretsViewModel

    @Environment(\.dismiss) private var dismiss

    // Wizard phase
    @State private var phase: Phase = .configure

    // Configuration toggles
    @State private var includeKeychainHelper: Bool = true
    @State private var includeExportStatements: Bool = true
    @State private var includePathEntries: Bool = false
    @State private var includeEnvVars: Bool = false

    // Loaded data
    @State private var pathEntries: [String] = []
    @State private var envVars: [(key: String, value: String)] = []
    @State private var isLoadingData: Bool = false

    // Password
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var passwordError: String?

    // Generation
    @State private var isGenerating: Bool = false
    @State private var generationError: String?

    private enum Phase {
        case configure
        case password
        case generating
    }

    private var passwordValid: Bool {
        password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Generate Setup Script")
                    .font(.headline)

                Spacer()

                // Spacer button to balance layout
                Button("Cancel") { }
                    .opacity(0)
                    .disabled(true)
            }
            .padding()

            Divider()

            switch phase {
            case .configure:
                configurePhase
            case .password:
                passwordPhase
            case .generating:
                generatingPhase
            }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Phase 1: Configure

    private var configurePhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Keychain Secrets") {
                    LabeledContent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } label: {
                        Label("Encrypted secrets (\(viewModel.secrets.count) keys)", systemImage: "key.fill")
                    }
                }

                Section("Shell Configuration") {
                    Toggle(isOn: $includeKeychainHelper) {
                        Label("keychain_secret() helper function", systemImage: "terminal")
                    }

                    Toggle(isOn: $includeExportStatements) {
                        Label("Export statements for secrets", systemImage: "text.badge.plus")
                    }
                    .disabled(!includeKeychainHelper)

                    Toggle(isOn: $includePathEntries) {
                        Label("PATH entries", systemImage: "folder")
                    }

                    Toggle(isOn: $includeEnvVars) {
                        Label("Environment variables", systemImage: "list.bullet.rectangle")
                    }
                }

                Section {
                    Text("The generated script will decrypt secrets and configure your shell on a new machine.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Next") { prepareAndAdvance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoadingData)

                if isLoadingData {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
        }
    }

    // MARK: - Phase 2: Password

    private var passwordPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set a password to encrypt the secrets in the setup script. You'll need this password when running the script on another machine.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField("Enter password (8+ characters)", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: password) { passwordError = nil }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField("Re-enter password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: confirmPassword) { passwordError = nil }
            }

            if password.count > 0 && password.count < 8 {
                Label("Password must be at least 8 characters", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !confirmPassword.isEmpty && password != confirmPassword {
                Label("Passwords do not match", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let error = passwordError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Back") { phase = .configure }
                Spacer()
                Button("Generate") { generateScript() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!passwordValid)
            }
        }
        .padding(20)
    }

    // MARK: - Phase 3: Generating

    private var generatingPhase: some View {
        VStack(spacing: 20) {
            Spacer()

            if isGenerating {
                ProgressView("Generating setup script...")
                Text("Reading secret values and encrypting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = generationError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Generation Failed")
                    .font(.headline)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    phase = .password
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func prepareAndAdvance() {
        isLoadingData = true

        Task {
            // Load PATH entries if requested
            if includePathEntries {
                let pathVM = PathManagerViewModel()
                pathVM.load()
                pathEntries = pathVM.entries.map(\.path)
            }

            // Load env vars if requested
            if includeEnvVars {
                let envVM = EnvVarsViewModel()
                envVM.load()
                envVars = envVM.variables
                    .filter { $0.key != "PATH" }
                    .map { (key: $0.key, value: $0.value) }
            }

            // If helper is off, export statements make no sense
            if !includeKeychainHelper {
                includeExportStatements = false
            }

            isLoadingData = false
            phase = .password
        }
    }

    private func generateScript() {
        phase = .generating
        isGenerating = true
        generationError = nil

        Task {
            do {
                // Gather all secret values
                let secretsWithValues = await viewModel.gatherSecretsWithValues()

                guard !secretsWithValues.isEmpty else {
                    generationError = "No secret values could be read from the keychain."
                    isGenerating = false
                    return
                }

                let config = SetupScriptConfig(
                    secrets: secretsWithValues,
                    includeKeychainHelper: includeKeychainHelper,
                    includeExportStatements: includeExportStatements,
                    pathEntries: includePathEntries ? pathEntries : [],
                    envVars: includeEnvVars ? envVars : [],
                    password: password
                )

                let script = try await SetupScriptGenerator.generate(config: config)

                let fileType = ExportFileType(
                    defaultName: "shellcraft-setup.sh",
                    allowedContentTypes: [.shellScript]
                )

                let saved = ImportExportService.export(content: script, fileType: fileType)

                isGenerating = false

                if saved {
                    dismiss()
                } else {
                    // User cancelled the save panel — go back to password
                    phase = .password
                }
            } catch {
                generationError = error.localizedDescription
                isGenerating = false
            }
        }
    }
}
