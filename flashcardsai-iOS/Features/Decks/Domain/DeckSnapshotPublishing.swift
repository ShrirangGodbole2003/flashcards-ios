import Foundation

/// Tells the outside world (today: the home-screen widget) which decks the signed-in user has.
/// View models depend on this protocol only, so they never import WidgetKit.
@MainActor
protocol DeckSnapshotPublishing {
    /// `decks` is the full list, newest first. The implementation decides how many to keep.
    func publish(decks: [DeckSummary])
    /// Forget everything (sign-out), so nothing of the previous account stays visible.
    func clear()
}

/// Default for previews and tests.
struct NoopDeckSnapshotPublisher: DeckSnapshotPublishing {
    // Usable as a default argument from non-isolated initializers.
    nonisolated init() {}

    func publish(decks: [DeckSummary]) {}
    func clear() {}
}
