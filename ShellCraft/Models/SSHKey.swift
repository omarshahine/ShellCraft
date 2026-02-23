import Foundation

struct SSHKey: Identifiable, Hashable {
    let id: UUID
    var path: String
    var type: KeyType
    var fingerprint: String
    var publicKey: String
    var hasPassphrase: Bool

    init(
        id: UUID = UUID(),
        path: String,
        type: KeyType = .ed25519,
        fingerprint: String = "",
        publicKey: String = "",
        hasPassphrase: Bool = false
    ) {
        self.id = id
        self.path = path
        self.type = type
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.hasPassphrase = hasPassphrase
    }

    enum KeyType: String, CaseIterable, Identifiable {
        case ed25519
        case rsa
        case ecdsa
        case dsa

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ed25519: "Ed25519"
            case .rsa: "RSA"
            case .ecdsa: "ECDSA"
            case .dsa: "DSA"
            }
        }
    }
}
