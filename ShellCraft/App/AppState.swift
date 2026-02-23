import SwiftUI

@MainActor @Observable
final class AppState {
    var selectedSection: SidebarSection? = .aliases
    var isLoading = false
    var globalError: String?

    // Track unsaved changes per section
    var unsavedSections: Set<SidebarSection> = []

    func markUnsaved(_ section: SidebarSection) {
        unsavedSections.insert(section)
    }

    func markSaved(_ section: SidebarSection) {
        unsavedSections.remove(section)
    }

    func hasUnsavedChanges(for section: SidebarSection) -> Bool {
        unsavedSections.contains(section)
    }
}
