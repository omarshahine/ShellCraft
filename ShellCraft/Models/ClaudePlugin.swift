import Foundation

struct ClaudePlugin: Identifiable, Hashable {
    let id: UUID
    var name: String
    var marketplace: String
    var enabled: Bool
    var version: String?

    init(
        id: UUID = UUID(),
        name: String,
        marketplace: String,
        enabled: Bool = true,
        version: String? = nil
    ) {
        self.id = id
        self.name = name
        self.marketplace = marketplace
        self.enabled = enabled
        self.version = version
    }

    var qualifiedName: String {
        "\(name)@\(marketplace)"
    }
}
