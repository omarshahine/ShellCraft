import Foundation

struct EnvironmentVariable: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String
    var sourceFile: String
    var lineNumber: Int
    var isKeychainDerived: Bool

    init(
        id: UUID = UUID(),
        key: String,
        value: String,
        sourceFile: String = "~/.zshrc",
        lineNumber: Int = 0,
        isKeychainDerived: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.sourceFile = sourceFile
        self.lineNumber = lineNumber
        self.isKeychainDerived = isKeychainDerived
    }
}
