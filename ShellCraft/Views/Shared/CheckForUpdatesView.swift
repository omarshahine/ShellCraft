import Combine
import Sparkle
import SwiftUI

/// Tracks whether Sparkle is currently able to start an update check.
///
/// Sparkle exposes `canCheckForUpdates` as a KVO-observable property rather
/// than an async sequence, so the menu item mirrors it through Combine. The
/// project builds with strict concurrency, hence the explicit main-actor
/// isolation: the value drives a SwiftUI menu item and is only ever read there.
@MainActor
final class UpdaterAvailability: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }
}

/// The "Check for Updates…" item in the ShellCraft menu.
///
/// Disabled while Sparkle is busy (already checking, or installing), which is
/// what `canCheckForUpdates` reports. Sparkle drives all the update UI itself,
/// so there is nothing else to present here.
struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    @StateObject private var availability: UpdaterAvailability

    init(updater: SPUUpdater) {
        self.updater = updater
        _availability = StateObject(wrappedValue: UpdaterAvailability(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!availability.canCheckForUpdates)
    }
}
