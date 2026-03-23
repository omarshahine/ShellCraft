import Foundation

// MARK: - Tab Enum

enum GhosttyTab: String, CaseIterable, Identifiable {
    case theme = "Theme"
    case appearance = "Appearance"
    case general = "General"

    var id: String { rawValue }
}

// MARK: - Config Entry

struct GhosttyConfigEntry: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

// MARK: - Config

struct GhosttyConfig: Equatable, Hashable {
    var entries: [GhosttyConfigEntry] = []

    /// Returns the value for a given key, or nil if not found.
    func value(for key: String) -> String? {
        entries.last(where: { $0.key == key })?.value
    }

    /// Sets the value for a key. Updates existing entry or appends a new one.
    mutating func setValue(for key: String, value: String) {
        if let index = entries.lastIndex(where: { $0.key == key }) {
            entries[index].value = value
        } else {
            entries.append(GhosttyConfigEntry(key: key, value: value))
        }
    }

    /// Removes all entries with the given key.
    mutating func removeValue(for key: String) {
        entries.removeAll { $0.key == key }
    }

    /// Returns entries whose keys are not in the given set (for the raw editor).
    func extraEntries(excluding knownKeys: Set<String>) -> [GhosttyConfigEntry] {
        entries.filter { !knownKeys.contains($0.key) }
    }
}

// MARK: - Theme

struct GhosttyTheme: Identifiable, Hashable {
    let name: String
    /// ANSI palette colors 0-15 as hex strings
    var palette: [Int: String] = [:]
    var background: String?
    var foreground: String?
    var cursorColor: String?
    var cursorText: String?
    var selectionBackground: String?
    var selectionForeground: String?

    var id: String { name }

    /// Returns the palette color for an index, or a default gray.
    func paletteHex(_ index: Int) -> String {
        palette[index] ?? "#808080"
    }
}
