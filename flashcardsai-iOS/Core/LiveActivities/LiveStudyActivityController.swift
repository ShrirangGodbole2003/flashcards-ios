import ActivityKit
import Foundation
import os

/// ActivityKit implementation of `StudyActivityControlling`.
///
/// Starting, updating and ending are `async` in ActivityKit, but callers are synchronous, so every
/// operation goes through one serial queue (`enqueue`). Without it, two quick updates could finish
/// out of order and the Lock Screen would show an older card count.
///
/// Everything fails soft: Live Activities can be turned off by the user, or refused by the system
/// (e.g. too many running); studying must never break because of that.
@MainActor
final class LiveStudyActivityController: StudyActivityControlling {
    private typealias StudyActivity = Activity<StudyActivityAttributes>
    private typealias State = StudyActivityAttributes.ContentState

    /// If the app stops updating (killed, crashed), iOS marks the activity outdated after this long.
    private static let staleAfter: TimeInterval = 30 * 60
    /// How long the "done" card stays on the Lock Screen after a finished session.
    private static let finishedLingerFor: TimeInterval = 5 * 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "flashcardsai",
                                       category: "liveactivity")

    private var activity: StudyActivity?
    private var pipeline: Task<Void, Never>?

    func start(deckID: Int, deckName: String, totalCards: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.logger.debug("Live Activities are turned off, skipping start")
            return
        }
        let attributes = StudyActivityAttributes(deckID: deckID, deckName: deckName, totalCards: totalCards)

        enqueue { [self] in
            await endEverything()   // one session at a time
            let state = State(answeredCount: 0, correctCount: 0, isFinished: false)
            do {
                activity = try StudyActivity.request(attributes: attributes, content: content(for: state))
            } catch {
                Self.logger.error("Could not start Live Activity: \(error.localizedDescription)")
            }
        }
    }

    func update(answeredCount: Int, correctCount: Int) {
        enqueue { [self] in
            guard let activity else { return }
            let state = State(answeredCount: answeredCount, correctCount: correctCount, isFinished: false)
            await activity.update(content(for: state))
        }
    }

    func end(answeredCount: Int, correctCount: Int, finished: Bool) {
        enqueue { [self] in
            guard let activity else { return }
            self.activity = nil
            if finished {
                let state = State(answeredCount: answeredCount, correctCount: correctCount, isFinished: true)
                await activity.end(ActivityContent(state: state, staleDate: nil),
                                   dismissalPolicy: .after(Date().addingTimeInterval(Self.finishedLingerFor)))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func endAll() {
        enqueue { [self] in await endEverything() }
    }

    // MARK: Private

    private func endEverything() async {
        activity = nil
        for running in StudyActivity.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func content(for state: State) -> ActivityContent<State> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
    }

    /// Runs `work` after everything queued before it has finished.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pipeline
        pipeline = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
