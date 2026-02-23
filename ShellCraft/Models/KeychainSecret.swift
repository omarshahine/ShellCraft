import Foundation

struct KeychainSecret: Identifiable, Hashable {
    let id: UUID
    var serviceName: String
    var account: String
    var displayKey: String
    var isReferenced: Bool

    init(
        id: UUID = UUID(),
        serviceName: String,
        account: String,
        displayKey: String = "",
        isReferenced: Bool = false
    ) {
        self.id = id
        self.serviceName = serviceName
        self.account = account
        self.displayKey = displayKey.isEmpty ? serviceName.replacingOccurrences(of: "env/", with: "") : displayKey
        self.isReferenced = isReferenced
    }
}
