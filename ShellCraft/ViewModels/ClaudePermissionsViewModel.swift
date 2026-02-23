import Foundation

@MainActor @Observable
final class ClaudePermissionsViewModel {

    // MARK: - Properties

    var permissions: [ClaudePermission] = []
    var searchText = ""
    var selectedCategory: PermissionCategory?
    var hasUnsavedChanges = false

    private var originalPermissions: [ClaudePermission] = []

    /// Editable permission mode setting.
    var defaultMode: String? {
        didSet { trackChanges() }
    }

    /// Preserved fields from the original settings that we don't edit in the UI.
    private var preservedAsk: [String]?
    private var preservedAdditionalDirectories: [String]?
    private var preservedDisableBypassPermissionsMode: String?

    private var originalDefaultMode: String?

    // MARK: - Computed Properties

    var allowCount: Int {
        permissions.count { $0.list == .allow }
    }

    var denyCount: Int {
        permissions.count { $0.list == .deny }
    }

    var filteredPermissions: [ClaudePermission] {
        permissions.filter { permission in
            let matchesSearch = searchText.isEmpty ||
                permission.pattern.lowercased().contains(searchText.lowercased())
            let matchesCategory = selectedCategory == nil || permission.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    var allowPermissions: [ClaudePermission] {
        filteredPermissions.filter { $0.list == .allow }
    }

    var denyPermissions: [ClaudePermission] {
        filteredPermissions.filter { $0.list == .deny }
    }

    var permissionsByCategory: [PermissionCategory: [ClaudePermission]] {
        Dictionary(grouping: filteredPermissions, by: \.category)
    }

    // MARK: - Load

    func load(from settings: ClaudeSettings) {
        var result: [ClaudePermission] = []

        if let allowPatterns = settings.permissions?.allow {
            for pattern in allowPatterns {
                result.append(ClaudePermission(pattern: pattern, list: .allow))
            }
        }

        if let denyPatterns = settings.permissions?.deny {
            for pattern in denyPatterns {
                result.append(ClaudePermission(pattern: pattern, list: .deny))
            }
        }

        // Load editable permission mode
        defaultMode = settings.permissions?.defaultMode
        originalDefaultMode = settings.permissions?.defaultMode

        // Preserve fields we don't edit in the UI
        preservedAsk = settings.permissions?.ask
        preservedAdditionalDirectories = settings.permissions?.additionalDirectories
        preservedDisableBypassPermissionsMode = settings.permissions?.disableBypassPermissionsMode

        permissions = result
        originalPermissions = result
        hasUnsavedChanges = false
    }

    // MARK: - Convert Back

    func toSettings() -> ClaudePermissions {
        let allowPatterns = permissions.filter { $0.list == .allow }.map(\.pattern)
        let denyPatterns = permissions.filter { $0.list == .deny }.map(\.pattern)

        return ClaudePermissions(
            allow: allowPatterns.isEmpty ? nil : allowPatterns,
            deny: denyPatterns.isEmpty ? nil : denyPatterns,
            ask: preservedAsk,
            defaultMode: defaultMode,
            additionalDirectories: preservedAdditionalDirectories,
            disableBypassPermissionsMode: preservedDisableBypassPermissionsMode
        )
    }

    // MARK: - Mutations

    func add(pattern: String, list: ClaudePermission.PermissionList) {
        let permission = ClaudePermission(pattern: pattern, list: list)
        permissions.append(permission)
        trackChanges()
    }

    func remove(_ permission: ClaudePermission) {
        permissions.removeAll { $0.id == permission.id }
        trackChanges()
    }

    func move(_ permission: ClaudePermission, to list: ClaudePermission.PermissionList) {
        guard let index = permissions.firstIndex(where: { $0.id == permission.id }) else { return }
        permissions[index] = ClaudePermission(
            id: permission.id,
            pattern: permission.pattern,
            list: list,
            category: permission.category
        )
        trackChanges()
    }

    func update(_ permission: ClaudePermission, pattern: String, list: ClaudePermission.PermissionList) {
        guard let index = permissions.firstIndex(where: { $0.id == permission.id }) else { return }
        permissions[index] = ClaudePermission(
            id: permission.id,
            pattern: pattern,
            list: list
        )
        trackChanges()
    }

    // MARK: - Change Tracking

    func markSaved() {
        originalPermissions = permissions
        originalDefaultMode = defaultMode
        hasUnsavedChanges = false
    }

    private func trackChanges() {
        hasUnsavedChanges = permissions.map(\.pattern) != originalPermissions.map(\.pattern) ||
            permissions.map(\.list) != originalPermissions.map(\.list) ||
            defaultMode != originalDefaultMode
    }
}
