import SwiftUI

struct HookEditorSheet: View {
    let mode: Mode
    let onSave: (HookEventType, ClaudeHook) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var eventType: HookEventType
    @State private var matcher: String
    @State private var handlerType: ClaudeHook.HandlerType
    @State private var commandValue: String
    @State private var promptValue: String
    @State private var agentValue: String
    @State private var timeoutString: String
    @State private var hookId: UUID

    enum Mode {
        case add
        case edit(event: HookEventType, hook: ClaudeHook)

        var title: String {
            switch self {
            case .add: "Add Hook"
            case .edit: "Edit Hook"
            }
        }

        var isEdit: Bool {
            switch self {
            case .add: false
            case .edit: true
            }
        }
    }

    init(mode: Mode, onSave: @escaping (HookEventType, ClaudeHook) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .add:
            _eventType = State(initialValue: .preToolUse)
            _matcher = State(initialValue: "")
            _handlerType = State(initialValue: .command)
            _commandValue = State(initialValue: "")
            _promptValue = State(initialValue: "")
            _agentValue = State(initialValue: "")
            _timeoutString = State(initialValue: "")
            _hookId = State(initialValue: UUID())
        case .edit(let event, let hook):
            _eventType = State(initialValue: event)
            _matcher = State(initialValue: hook.matcher ?? "")
            _handlerType = State(initialValue: hook.handlerType)
            _commandValue = State(initialValue: hook.command ?? "")
            _promptValue = State(initialValue: hook.prompt ?? "")
            _agentValue = State(initialValue: hook.agent ?? "")
            _timeoutString = State(initialValue: hook.timeout.map { String($0) } ?? "")
            _hookId = State(initialValue: hook.id)
        }
    }

    private var isValid: Bool {
        switch handlerType {
        case .command: !commandValue.trimmed.isEmpty
        case .prompt: !promptValue.trimmed.isEmpty
        case .agent: !agentValue.trimmed.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Picker("Event Type", selection: $eventType) {
                        ForEach(HookEventType.allCases) { event in
                            Text(event.rawValue).tag(event)
                        }
                    }
                    .disabled(mode.isEdit)

                    Text(eventDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Matcher") {
                    TextField("Tool name pattern (optional)", text: $matcher)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Filter by tool name. Leave empty to match all tools for this event.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Handler") {
                    Picker("Handler Type", selection: $handlerType) {
                        ForEach(ClaudeHook.HandlerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch handlerType {
                    case .command:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shell command to execute:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            CodeEditorView(
                                text: $commandValue,
                                language: "bash",
                                lineNumbers: false,
                                isEditable: true
                            )
                            .frame(height: 80)
                        }
                    case .prompt:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Prompt text for Claude to evaluate:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $promptValue)
                                .font(.body)
                                .frame(height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    case .agent:
                        TextField("Agent name or path", text: $agentValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("Timeout") {
                    HStack {
                        TextField("Timeout in ms (optional)", text: $timeoutString)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        Text("ms")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveHook() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(width: 520, height: 520)
    }

    private func saveHook() {
        var hook = ClaudeHook(id: hookId)
        hook.matcher = matcher.trimmed.isEmpty ? nil : matcher.trimmed

        switch handlerType {
        case .command:
            hook.command = commandValue.trimmed
        case .prompt:
            hook.prompt = promptValue.trimmed
        case .agent:
            hook.agent = agentValue.trimmed
        }

        if let timeout = Int(timeoutString.trimmed), timeout > 0 {
            hook.timeout = timeout
        }

        onSave(eventType, hook)
        dismiss()
    }

    private var eventDescription: String {
        switch eventType {
        case .preToolUse:
            "Runs before a tool is executed. Can block tool calls."
        case .postToolUse:
            "Runs after a tool has executed."
        case .notification:
            "Runs when Claude sends a notification."
        case .stop:
            "Runs when Claude stops its main loop."
        case .subagentStop:
            "Runs when a subagent stops."
        case .permissionRequest:
            "Runs when a permission is requested. Can log or audit tool use."
        }
    }
}
