import Foundation

/// What the study screen needs from a "session progress" Live Activity. The view model depends on
/// this protocol only, so it never imports ActivityKit and stays testable.
@MainActor
protocol StudyActivityControlling {
    /// Starts an activity for a new session. Replaces any activity that is still showing.
    func start(deckID: Int, deckName: String, totalCards: Int)
    /// Progress after a card was graded.
    func update(answeredCount: Int, correctCount: Int)
    /// Ends the current activity. `finished == true` leaves a "done" card on screen for a few minutes;
    /// `false` (user left early) removes it at once.
    func end(answeredCount: Int, correctCount: Int, finished: Bool)
    /// Removes every study activity: stale ones from a previous launch, or on sign-out.
    func endAll()
}

/// Default for previews and tests.
struct NoopStudyActivityController: StudyActivityControlling {
    // Usable as a default argument from non-isolated initializers.
    nonisolated init() {}

    func start(deckID: Int, deckName: String, totalCards: Int) {}
    func update(answeredCount: Int, correctCount: Int) {}
    func end(answeredCount: Int, correctCount: Int, finished: Bool) {}
    func endAll() {}
}
