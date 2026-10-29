import Foundation

/// Pure state machine for one run through a deck. No UI, no I/O, so it is fully unit-testable.
///
/// Per card type:
///  - MCQ:        `selectOption`            -> graded automatically
///  - TRUE_FALSE: `answerTrueFalse`         -> graded automatically
///  - QA:         `revealAnswer` then `gradeSelf` (the user says if they knew it)
/// then `advance()` moves to the next card.
struct StudySession: Equatable, Sendable {
    enum Selection: Equatable, Sendable {
        case option(Int)
        case trueFalse(Bool)
        case revealedOnly          // QA: the answer was shown, not yet self-graded
    }

    enum Phase: Equatable, Sendable {
        case answering
        /// `isCorrect == nil` only for QA cards waiting for self-grading.
        case revealed(selection: Selection, isCorrect: Bool?)
    }

    struct Result: Equatable, Hashable, Sendable {
        let cardID: Int
        let isCorrect: Bool
    }

    let cards: [Card]
    private(set) var currentIndex = 0
    private(set) var phase: Phase = .answering
    private(set) var results: [Result] = []

    init(cards: [Card]) {
        self.cards = cards
    }

    // MARK: Derived state

    var currentCard: Card? {
        cards.indices.contains(currentIndex) ? cards[currentIndex] : nil
    }

    var isFinished: Bool { currentIndex >= cards.count }
    var totalCount: Int { cards.count }
    var correctCount: Int { results.filter(\.isCorrect).count }

    /// Fraction of cards completed (0...1), for the progress bar.
    var progress: Double {
        guard !cards.isEmpty else { return 1 }
        return Double(currentIndex) / Double(cards.count)
    }

    var isRevealed: Bool {
        if case .revealed = phase { return true }
        return false
    }

    var needsSelfGrade: Bool {
        if case .revealed(_, nil) = phase { return true }
        return false
    }

    var canAdvance: Bool {
        if case .revealed(_, .some) = phase { return true }
        return false
    }

    var isLastCard: Bool { currentIndex == cards.count - 1 }

    var missedCards: [Card] {
        let missed = Set(results.filter { !$0.isCorrect }.map(\.cardID))
        return cards.filter { missed.contains($0.id) }
    }

    var accuracy: Double {
        guard !cards.isEmpty else { return 0 }
        return Double(correctCount) / Double(cards.count)
    }

    // MARK: Actions

    mutating func selectOption(_ index: Int) {
        guard case .answering = phase, let card = currentCard, card.type == .mcq,
              card.options.indices.contains(index) else { return }

        let correct: Bool
        if let correctIndex = card.correctIndex, card.options.indices.contains(correctIndex) {
            correct = index == correctIndex
        } else {
            correct = card.options[index] == card.answer
        }
        record(card, selection: .option(index), isCorrect: correct)
    }

    mutating func answerTrueFalse(_ value: Bool) {
        guard case .answering = phase, let card = currentCard, card.type == .trueFalse else { return }
        let correctValue = card.answer.caseInsensitiveCompare("True") == .orderedSame
        record(card, selection: .trueFalse(value), isCorrect: value == correctValue)
    }

    mutating func revealAnswer() {
        guard case .answering = phase, let card = currentCard, card.type == .qa else { return }
        phase = .revealed(selection: .revealedOnly, isCorrect: nil)
    }

    mutating func gradeSelf(correct: Bool) {
        guard case .revealed(let selection, nil) = phase, let card = currentCard else { return }
        record(card, selection: selection, isCorrect: correct)
    }

    mutating func advance() {
        guard canAdvance else { return }
        currentIndex += 1
        phase = .answering
    }

    mutating func restart() {
        self = StudySession(cards: cards)
    }

    private mutating func record(_ card: Card, selection: Selection, isCorrect: Bool) {
        results.append(Result(cardID: card.id, isCorrect: isCorrect))
        phase = .revealed(selection: selection, isCorrect: isCorrect)
    }
}
