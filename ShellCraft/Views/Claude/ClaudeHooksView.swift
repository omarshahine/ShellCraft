import SwiftUI

struct ClaudeHooksView: View {
    @Bindable var viewModel: ClaudeHooksViewModel
    @State private var showAddSheet = false
    @State private var editingHook: (event: HookEventType, hook: ClaudeHook)?

    var body: some View {
        List {
            if viewModel.totalHookCount == 0 {
                ContentUnavailableView {
                    Label("No Hooks Configured", systemImage: "arrow.triangle.turn.up.right.diamond")
                } description: {
                    Text("Hooks let you run commands, prompts, or agents at specific lifecycle events.")
                } actions: {
                    Button("Add Hook") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(viewModel.allEventTypes) { eventType in
                    let hooks = viewModel.hooksByEvent[eventType] ?? []
                    if !hooks.isEmpty {
                        Section {
                            ForEach(hooks) { hook in
                                hookRow(hook, event: eventType)
                                    .contextMenu {
                                        Button("Edit") {
                                            editingHook = (event: eventType, hook: hook)
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            viewModel.remove(event: eventType, hook: hook)
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                eventIcon(eventType)
                                Text(eventType.rawValue)
                                    .font(.headline)
                                Spacer()
                                Text("\(hooks.count)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Hook", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            HookEditorSheet(mode: .add) { event, hook in
                viewModel.add(event: event, hook: hook)
            }
        }
        .sheet(item: Binding(
            get: { editingHook.map { EditableHook(event: $0.event, hook: $0.hook) } },
            set: { editingHook = $0.map { ($0.event, $0.hook) } }
        )) { editable in
            HookEditorSheet(mode: .edit(event: editable.event, hook: editable.hook)) { event, hook in
                viewModel.update(event: event, hook: hook)
            }
        }
    }

    // MARK: - Hook Row

    private func hookRow(_ hook: ClaudeHook, event: HookEventType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Handler type badge
                handlerTypeBadge(hook.handlerType)

                // Matcher
                if let matcher = hook.matcher, !matcher.isEmpty {
                    Text(matcher)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                } else {
                    Text("(no matcher)")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Timeout badge
                if let timeout = hook.timeout {
                    Text("\(timeout)ms")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            // Handler preview
            Group {
                switch hook.handlerType {
                case .command:
                    Text(hook.command ?? "")
                        .font(.system(.caption, design: .monospaced))
                case .prompt:
                    Text(hook.prompt ?? "")
                        .font(.caption)
                case .agent:
                    Text(hook.agent ?? "")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Badges

    private func handlerTypeBadge(_ type: ClaudeHook.HandlerType) -> some View {
        Text(type.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(handlerColor(type).opacity(0.15))
            .foregroundStyle(handlerColor(type))
            .clipShape(Capsule())
    }

    private func handlerColor(_ type: ClaudeHook.HandlerType) -> Color {
        switch type {
        case .command: .blue
        case .prompt: .green
        case .agent: .purple
        }
    }

    private func eventIcon(_ event: HookEventType) -> some View {
        let (name, color): (String, Color) = switch event {
        case .preToolUse: ("arrow.right.circle", .orange)
        case .postToolUse: ("arrow.left.circle", .blue)
        case .notification: ("bell", .green)
        case .stop: ("stop.circle", .red)
        case .subagentStop: ("person.crop.circle.badge.xmark", .purple)
        case .permissionRequest: ("lock.shield", .teal)
        }

        return Image(systemName: name)
            .foregroundStyle(color)
    }
}

// MARK: - Identifiable wrapper for editing state

private struct EditableHook: Identifiable {
    let id: UUID
    let event: HookEventType
    let hook: ClaudeHook

    init(event: HookEventType, hook: ClaudeHook) {
        self.id = hook.id
        self.event = event
        self.hook = hook
    }
}
