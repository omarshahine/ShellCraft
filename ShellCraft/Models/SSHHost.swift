import Foundation

struct SSHHost: Identifiable, Hashable {
    let id: UUID
    var host: String
    var hostname: String
    var user: String
    var identityFile: String
    var port: Int?
    var options: [String: String]

    init(
        id: UUID = UUID(),
        host: String,
        hostname: String = "",
        user: String = "",
        identityFile: String = "",
        port: Int? = nil,
        options: [String: String] = [:]
    ) {
        self.id = id
        self.host = host
        self.hostname = hostname
        self.user = user
        self.identityFile = identityFile
        self.port = port
        self.options = options
    }
}
