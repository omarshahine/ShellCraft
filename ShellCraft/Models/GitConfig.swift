import Foundation

struct GitConfig: Identifiable, Hashable {
    let id: UUID
    var sections: [GitConfigSection]

    init(id: UUID = UUID(), sections: [GitConfigSection] = []) {
        self.id = id
        self.sections = sections
    }

    func value(section: String, subsection: String? = nil, key: String) -> String? {
        sections.first { $0.name == section && $0.subsection == subsection }?
            .entries.first { $0.key == key }?.value
    }

    mutating func setValue(section: String, subsection: String? = nil, key: String, value: String) {
        if let sectionIndex = sections.firstIndex(where: { $0.name == section && $0.subsection == subsection }) {
            if let entryIndex = sections[sectionIndex].entries.firstIndex(where: { $0.key == key }) {
                sections[sectionIndex].entries[entryIndex].value = value
            } else {
                sections[sectionIndex].entries.append(GitConfigEntry(key: key, value: value))
            }
        } else {
            var newSection = GitConfigSection(name: section, subsection: subsection)
            newSection.entries.append(GitConfigEntry(key: key, value: value))
            sections.append(newSection)
        }
    }
}

struct GitConfigSection: Identifiable, Hashable {
    let id: UUID
    var name: String
    var subsection: String?
    var entries: [GitConfigEntry]

    init(id: UUID = UUID(), name: String, subsection: String? = nil, entries: [GitConfigEntry] = []) {
        self.id = id
        self.name = name
        self.subsection = subsection
        self.entries = entries
    }

    var displayName: String {
        if let subsection {
            "[\(name) \"\(subsection)\"]"
        } else {
            "[\(name)]"
        }
    }
}

struct GitConfigEntry: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}
