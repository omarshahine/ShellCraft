import Foundation

@MainActor @Observable
final class ClaudeHooksViewModel {

    // MARK: - Properties

    var hooksByEvent: [HookEventType: [ClaudeHook]] = [:]
    var hasUnsavedChanges = false

    private var originalHooksByEvent: [HookEventType: [ClaudeHook]] = [:]

    // MARK: - Computed

    var totalHookCount: Int {
        hooksByEvent.values.reduce(0) { $0 + $1.count }
    }

    /// Returns event types that have hooks, sorted by display order
    var activeEventTypes: [HookEventType] {
        HookEventType.allCases.filter { hooksByEvent[$0]?.isEmpty == false }
    }

    /// Returns all event types for the add-hook picker
    var allEventTypes: [HookEventType] {
        HookEventType.allCases
    }

    // MARK: - Load

    func load(from settings: ClaudeSettings) {
        var result: [HookEventType: [ClaudeHook]] = [:]

        if let hooks = settings.hooks {
            for (eventKey, hookArray) in hooks {
                if let eventType = HookEventType(rawValue: eventKey) {
                    result[eventType] = hookArray
                }
            }
        }

        hooksByEvent = result
        originalHooksByEvent = result
        hasUnsavedChanges = false
    }

    // MARK: - Convert Back

    func toSettings() -> [String: [ClaudeHook]]? {
        var result: [String: [ClaudeHook]] = [:]

        for (event, hooks) in hooksByEvent where !hooks.isEmpty {
            result[event.rawValue] = hooks
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Mutations

    func add(event: HookEventType, hook: ClaudeHook) {
        if hooksByEvent[event] == nil {
            hooksByEvent[event] = []
        }
        hooksByEvent[event]?.append(hook)
        trackChanges()
    }

    func update(event: HookEventType, hook: ClaudeHook) {
        guard var hooks = hooksByEvent[event],
              let index = hooks.firstIndex(where: { $0.id == hook.id })
        else { return }
        hooks[index] = hook
        hooksByEvent[event] = hooks
        trackChanges()
    }

    func remove(event: HookEventType, hook: ClaudeHook) {
        hooksByEvent[event]?.removeAll { $0.id == hook.id }
        // Clean up empty arrays
        if hooksByEvent[event]?.isEmpty == true {
            hooksByEvent.removeValue(forKey: event)
        }
        trackChanges()
    }

    func removeAll(for event: HookEventType) {
        hooksByEvent.removeValue(forKey: event)
        trackChanges()
    }

    // MARK: - Change Tracking

    func markSaved() {
        originalHooksByEvent = hooksByEvent
        hasUnsavedChanges = false
    }

    private func trackChanges() {
        // Compare by serializing to check for actual differences
        let currentKeys = Set(hooksByEvent.keys)
        let originalKeys = Set(originalHooksByEvent.keys)

        if currentKeys != originalKeys {
            hasUnsavedChanges = true
            return
        }

        for key in currentKeys {
            let current = hooksByEvent[key] ?? []
            let original = originalHooksByEvent[key] ?? []
            if current.count != original.count {
                hasUnsavedChanges = true
                return
            }
            for (c, o) in zip(current, original) {
                if c.matcher != o.matcher || c.command != o.command ||
                   c.prompt != o.prompt || c.agent != o.agent || c.timeout != o.timeout {
                    hasUnsavedChanges = true
                    return
                }
            }
        }

        hasUnsavedChanges = false
    }
}
