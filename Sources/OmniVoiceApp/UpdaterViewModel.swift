import Combine
import Sparkle

/// Wraps Sparkle's updater so the menu bar can offer "Check for Updates…".
///
/// Sparkle reads `SUFeedURL` (the appcast) and `SUPublicEDKey` from Info.plist,
/// downloads the newest build, verifies its EdDSA signature *and* Apple
/// notarization, then installs and relaunches. OmniSpeak ships via Developer ID
/// (outside the App Store), so this is how users receive updates.
@MainActor
final class UpdaterViewModel: ObservableObject {
    /// False briefly at launch and while a check is already running.
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true begins scheduled background checks immediately,
        // using the feed URL + public key from Info.plist.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
