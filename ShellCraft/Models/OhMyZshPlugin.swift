import Foundation

struct OhMyZshPlugin: Identifiable, Hashable {
    let name: String
    var description: String
    var isEnabled: Bool
    let isCustom: Bool

    var id: String { name }

    // Hash/equality based on name only (identity), not mutable state
    static func == (lhs: OhMyZshPlugin, rhs: OhMyZshPlugin) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
