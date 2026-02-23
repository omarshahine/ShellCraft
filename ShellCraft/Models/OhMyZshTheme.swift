import Foundation

struct OhMyZshTheme: Identifiable, Hashable {
    let name: String
    let isCustom: Bool

    var id: String { name }
}
