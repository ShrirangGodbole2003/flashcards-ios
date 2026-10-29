import ActivityKit
import Foundation

/// Data model of the "study session" Live Activity. Compiled into the app (which starts and updates
/// the activity) and the widget extension (which draws it), so both sides agree on the shape.
///
/// Keep it small: the system caps an activity's data at about 4 KB.
struct StudyActivityAttributes: ActivityAttributes {
    /// The part that changes while the activity runs. Pushed on every update.
    struct ContentState: Codable, Hashable {
        /// Cards finished so far (graded). 0 at the start, `totalCards` when done.
        var answeredCount: Int
        var correctCount: Int
        var isFinished: Bool
    }

    // Fixed when the activity starts.
    let deckID: Int
    let deckName: String
    let totalCards: Int

    /// "Card 5 of 12": the card being worked on, never past the last one.
    func cardNumber(for state: ContentState) -> Int {
        guard totalCards > 0 else { return 0 }
        return min(state.answeredCount + 1, totalCards)
    }

    /// 0...1, for the progress bar.
    func progress(for state: ContentState) -> Double {
        guard totalCards > 0 else { return 1 }
        return min(Double(state.answeredCount) / Double(totalCards), 1)
    }
}
