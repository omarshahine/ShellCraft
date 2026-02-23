import Foundation

extension URL {
    static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    static func home(_ relativePath: String) -> URL {
        homeDirectory.appendingPathComponent(relativePath)
    }

    /// Replaces the home directory prefix with ~ for display
    var abbreviatingWithTilde: String {
        let home = NSHomeDirectory()
        let path = self.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
