import Foundation
import Observation

/// Holds "where should the app go" as plain state. Views never parse URLs: the app root hands
/// parsed `DeepLink`s to `receive(_:)`, and the tab views read `selectedTab` / `decksPath`.
///
/// A link is first stored as `pendingLink` and applied later by `applyPending(decks:)`, because
/// it can arrive before the app is ready (still launching, signed out, deck list not loaded).
/// Rule: a deck link only opens a deck that is already in the loaded list, nothing is fetched for it.
@MainActor
@Observable
final class DeepLinkRouter {
    var selectedTab: AppTab = .decks
    var decksPath: [DecksRoute] = []

    private(set) var pendingLink: DeepLink?
    /// Set when a link could not be opened (e.g. unknown deck). The UI shows it once, then calls `dismissNotice()`.
    private(set) var notice: String?

    /// Entry point for the URL handler. A newer link replaces an unapplied older one.
    func receive(_ link: DeepLink) {
        pendingLink = link
    }

    /// Applies the pending link, if any. Call it when the signed-in UI is on screen.
    /// - Parameter decks: the loaded deck list, or nil while it has not loaded yet.
    ///   A deck link stays pending until the list is available.
    func applyPending(decks: [DeckSummary]?) {
        guard let link = pendingLink else { return }

        switch link {
        case .decks:
            selectedTab = .decks
            decksPath = []
        case .score:
            selectedTab = .score
        case .profile:
            selectedTab = .profile
        case .deck(let id):
            guard let decks else { return }
            if let summary = decks.first(where: { $0.id == id }) {
                selectedTab = .decks
                decksPath = [.detail(summary)]
            } else {
                notice = "That deck isn't available on this device."
            }
        }
        pendingLink = nil
    }

    func dismissNotice() {
        notice = nil
    }

    /// Forget everything. Used on sign-out so one account's link never opens in another's session.
    func reset() {
        pendingLink = nil
        notice = nil
        selectedTab = .decks
        decksPath = []
    }
}
