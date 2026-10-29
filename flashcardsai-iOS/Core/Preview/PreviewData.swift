#if DEBUG
import Foundation

/// Sample data + in-memory fakes so SwiftUI previews work without the backend or Gemini.
enum PreviewData {
    static let user = AuthUser(id: 1, email: "alice@example.com")

    static let deck = Deck(
        id: 1, topic: "Swift concurrency", difficulty: .intermediate,
        cards: [
            Card(id: 1, type: .mcq,
                 question: "Which keyword marks a function that can suspend?",
                 answer: "async", options: ["await", "async", "defer", "actor"], correctIndex: 1,
                 explanation: "`async` marks a function that may suspend; callers use `await`.",
                 hint: "It appears in the function signature."),
            Card(id: 2, type: .qa,
                 question: "What problem does an actor solve?",
                 answer: "It serialises access to its mutable state, preventing data races.",
                 options: [], correctIndex: nil,
                 explanation: "Only one task at a time can run actor-isolated code.",
                 hint: "Think about shared mutable state."),
            Card(id: 3, type: .trueFalse,
                 question: "A `Task {}` created inside an actor always runs on a background thread.",
                 answer: "False", options: [], correctIndex: nil,
                 explanation: "It inherits the actor's isolation.", hint: nil),
        ])

    static let summaries: [DeckSummary] = [
        DeckSummary(id: 1, topic: "Swift concurrency", difficulty: .intermediate, cardCount: 6, createdAt: Date()),
        DeckSummary(id: 2, topic: "Docker basics", difficulty: .beginner, cardCount: 6, createdAt: Date().addingTimeInterval(-86_400)),
        DeckSummary(id: 3, topic: "Organic chemistry", difficulty: .advanced, cardCount: 6, createdAt: Date().addingTimeInterval(-172_800)),
    ]

    static let scores: [ScoreRecord] = [
        ScoreRecord(id: UUID(), deckID: 1, deckTopic: "Swift concurrency", difficulty: .intermediate, correct: 5, total: 6, date: Date()),
        ScoreRecord(id: UUID(), deckID: 2, deckTopic: "Docker basics", difficulty: .beginner, correct: 3, total: 6, date: Date().addingTimeInterval(-86_400)),
    ]
}

struct PreviewDeckRepository: DeckRepository {
    func fetchDecks() async throws -> [DeckSummary] { PreviewData.summaries }
    func fetchDeck(id: Int) async throws -> Deck { PreviewData.deck }
    func createDeck(topic: String, difficulty: Difficulty) async throws -> Deck {
        try await Task.sleep(for: .seconds(2))
        return PreviewData.deck
    }
    func deleteDeck(id: Int) async throws {}
}

struct PreviewScoreRepository: ScoreRepository {
    var records: [ScoreRecord] = PreviewData.scores
    func save(_ record: ScoreRecord) async {}
    func records() async -> [ScoreRecord] { records }
}

struct PreviewAuthRepository: AuthRepository {
    func register(email: String, password: String) async throws -> AuthUser { PreviewData.user }
    func login(email: String, password: String) async throws -> AuthUser { PreviewData.user }
    func restoreSession() async throws -> AuthUser? { PreviewData.user }
    func logout() async {}
}
#endif
