import SwiftUI

struct StatusBadge: View {
    let status: Status

    enum Status {
        case valid
        case invalid
        case warning
        case unknown

        var color: Color {
            switch self {
            case .valid: .green
            case .invalid: .red
            case .warning: .orange
            case .unknown: .gray
            }
        }

        var icon: String {
            switch self {
            case .valid: "checkmark.circle.fill"
            case .invalid: "xmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }
    }

    var body: some View {
        Image(systemName: status.icon)
            .foregroundStyle(status.color)
            .font(.caption)
    }
}
