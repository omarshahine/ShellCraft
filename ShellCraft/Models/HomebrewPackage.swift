import Foundation

struct HomebrewPackage: Identifiable, Hashable {
    let id: UUID
    var name: String
    var version: String
    var isFormula: Bool
    var description: String
    var isInstalled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        version: String = "",
        isFormula: Bool = true,
        description: String = "",
        isInstalled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.isFormula = isFormula
        self.description = description
        self.isInstalled = isInstalled
    }
}
