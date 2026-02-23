import Foundation

struct ShellFunction: Identifiable, Hashable {
    let id: UUID
    var name: String
    var body: String
    var sourceFile: String
    var lineRange: ClosedRange<Int>
    var description: String

    init(
        id: UUID = UUID(),
        name: String,
        body: String,
        sourceFile: String,
        lineRange: ClosedRange<Int>,
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.sourceFile = sourceFile
        self.lineRange = lineRange
        self.description = description
    }

    /// Full function text including declaration and braces
    var fullText: String {
        "\(name)() {\n\(body)\n}"
    }
}
