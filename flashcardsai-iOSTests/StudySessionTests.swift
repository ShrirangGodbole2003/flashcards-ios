import Foundation
import Testing
@testable import flashcardsai_iOS

struct StudySessionTests {
    // MARK: MCQ

    @Test func correctOptionIsGradedAutomatically() {
        var session = StudySession(cards: [TestData.mcq(correctIndex: 1)])
        session.selectOption(1)

        #expect(session.phase == .revealed(selection: .option(1), isCorrect: true))
        #expect(session.isRevealed)
        #expect(session.canAdvance)
        #expect(session.correctCount == 1)
    }

    @Test func wrongOptionIsGradedIncorrect() {
        var session = StudySession(cards: [TestData.mcq(correctIndex: 1)])
        session.selectOption(3)

        #expect(session.phase == .revealed(selection: .option(3), isCorrect: false))
        #expect(session.correctCount == 0)
        #expect(session.missedCards.count == 1)
    }

    @Test func invalidOptionIndexIsIgnored() {
        var session = StudySession(cards: [TestData.mcq()])
        session.selectOption(9)
        session.selectOption(-1)
        #expect(session.phase == .answering)
        #expect(session.results.isEmpty)
    }

    @Test func fallsBackToAnswerTextWhenCorrectIndexIsMissing() {
        let card = Card(id: 5, type: .mcq, question: "q", answer: "C", options: ["A", "B", "C", "D"],
                        correctIndex: nil, explanation: nil, hint: nil)
        var session = StudySession(cards: [card])
        session.selectOption(2)
        #expect(session.correctCount == 1)
    }

    @Test func secondTapOnAnswerIsIgnored() {
        var session = StudySession(cards: [TestData.mcq(correctIndex: 1)])
        session.selectOption(0)
        session.selectOption(1)     // user cannot change an answer after the flip
        #expect(session.results.count == 1)
        #expect(session.correctCount == 0)
    }

    // MARK: True / False

    @Test(arguments: [("True", true, true), ("True", false, false), ("False", false, true), ("false", true, false)])
    func trueFalseGrading(answer: String, chosen: Bool, expectedCorrect: Bool) {
        var session = StudySession(cards: [TestData.trueFalse(answer: answer)])
        session.answerTrueFalse(chosen)
        #expect(session.phase == .revealed(selection: .trueFalse(chosen), isCorrect: expectedCorrect))
    }

    // MARK: QA

    @Test func qaNeedsRevealThenSelfGrade() {
        var session = StudySession(cards: [TestData.qa()])

        session.revealAnswer()
        #expect(session.isRevealed)
        #expect(session.needsSelfGrade)
        #expect(!session.canAdvance)            // cannot skip grading
        session.advance()
        #expect(session.currentIndex == 0)

        session.gradeSelf(correct: true)
        #expect(session.canAdvance)
        #expect(session.correctCount == 1)
    }

    @Test func selfGradeBeforeRevealIsIgnored() {
        var session = StudySession(cards: [TestData.qa()])
        session.gradeSelf(correct: true)
        #expect(session.results.isEmpty)
    }

    @Test func actionsForTheWrongCardTypeAreIgnored() {
        var session = StudySession(cards: [TestData.qa()])
        session.selectOption(0)
        session.answerTrueFalse(true)
        #expect(session.phase == .answering)

        var mcq = StudySession(cards: [TestData.mcq()])
        mcq.revealAnswer()
        mcq.answerTrueFalse(true)
        #expect(mcq.phase == .answering)
    }

    // MARK: Whole run

    @Test func fullRunProducesScoreAndMissedCards() {
        var session = StudySession(cards: [TestData.qa(id: 1), TestData.mcq(id: 2, correctIndex: 1), TestData.trueFalse(id: 3)])
        #expect(session.progress == 0)

        session.revealAnswer(); session.gradeSelf(correct: true); session.advance()
        #expect(session.progress > 0.3 && session.progress < 0.4)

        session.selectOption(0)                 // wrong
        session.advance()

        #expect(session.isLastCard)
        session.answerTrueFalse(true)           // right ("True")
        session.advance()

        #expect(session.isFinished)
        #expect(session.progress == 1)
        #expect(session.currentCard == nil)
        #expect(session.correctCount == 2)
        #expect(session.totalCount == 3)
        #expect(abs(session.accuracy - 2.0 / 3.0) < 0.0001)
        #expect(session.missedCards.map(\.id) == [2])
    }

    @Test func advanceDoesNothingBeforeTheCardIsAnswered() {
        var session = StudySession(cards: [TestData.mcq()])
        session.advance()
        #expect(session.currentIndex == 0)
    }

    @Test func restartResetsEverything() {
        var session = StudySession(cards: [TestData.mcq()])
        session.selectOption(1)
        session.advance()
        #expect(session.isFinished)

        session.restart()
        #expect(!session.isFinished)
        #expect(session.results.isEmpty)
        #expect(session.phase == .answering)
    }

    @Test func emptyDeckIsImmediatelyFinished() {
        let session = StudySession(cards: [])
        #expect(session.isFinished)
        #expect(session.progress == 1)
        #expect(session.accuracy == 0)
    }
}
