import Foundation
import Observation

@MainActor
@Observable
final class StudyViewModel {
    let deck: Deck
    private(set) var session: StudySession
    private(set) var isHintVisible = false

    @ObservationIgnored private let scoreRepository: ScoreRepository
    @ObservationIgnored private let activityController: StudyActivityControlling
    @ObservationIgnored private var didSaveScore = false
    @ObservationIgnored private var isActivityRunning = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(deck: Deck,
         scoreRepository: ScoreRepository,
         activityController: StudyActivityControlling = NoopStudyActivityController()) {
        self.deck = deck
        self.scoreRepository = scoreRepository
        self.activityController = activityController
        self.session = StudySession(cards: deck.cards)
    }

    // MARK: Live Activity

    /// Called when the study screen appears (not from `init`: the navigation destination closure can
    /// build the same view model more than once, and each one would start an activity).
    func begin() {
        guard !isActivityRunning, !session.isFinished, session.totalCount > 0 else { return }
        startActivity()
    }

    /// Called when the study screen goes away. Removes the activity unless the session already ended it.
    func didLeave() {
        guard isActivityRunning else { return }
        isActivityRunning = false
        activityController.end(answeredCount: session.results.count,
                               correctCount: session.correctCount,
                               finished: false)
    }

    private func startActivity() {
        isActivityRunning = true
        activityController.start(deckID: deck.id, deckName: deck.topic, totalCards: session.totalCount)
    }

    // MARK: Card interaction

    func selectOption(_ index: Int) { session.selectOption(index) }
    func answerTrueFalse(_ value: Bool) { session.answerTrueFalse(value) }
    func revealAnswer() { session.revealAnswer() }
    func grade(correct: Bool) { session.gradeSelf(correct: correct) }
    func toggleHint() { isHintVisible.toggle() }

    func next() {
        session.advance()
        isHintVisible = false
        if session.isFinished {
            persistScore()
            finishActivity()
        } else if isActivityRunning {
            activityController.update(answeredCount: session.results.count, correctCount: session.correctCount)
        }
    }

    func restart() {
        session = StudySession(cards: deck.cards.shuffled())
        isHintVisible = false
        didSaveScore = false
        startActivity()     // replaces the finished activity with a fresh one
    }

    private func finishActivity() {
        guard isActivityRunning else { return }
        isActivityRunning = false
        activityController.end(answeredCount: session.results.count,
                               correctCount: session.correctCount,
                               finished: true)
    }

    // MARK: Scores

    /// Saved once per run, when the last card is done.
    private func persistScore() {
        guard !didSaveScore else { return }
        didSaveScore = true

        let record = ScoreRecord(id: UUID(),
                                 deckID: deck.id,
                                 deckTopic: deck.topic,
                                 difficulty: deck.difficulty,
                                 correct: session.correctCount,
                                 total: session.totalCount,
                                 date: Date())
        let repository = scoreRepository
        saveTask = Task { await repository.save(record) }
    }
}
