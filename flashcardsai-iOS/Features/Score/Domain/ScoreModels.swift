import Foundation

struct ScoreRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let deckID: Int
    let deckTopic: String
    let difficulty: Difficulty
    let correct: Int
    let total: Int
    let date: Date

    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

struct ScoreStats: Equatable, Sendable {
    let sessions: Int
    let cardsAnswered: Int
    let correctAnswers: Int
    let bestAccuracy: Double

    var averageAccuracy: Double {
        cardsAnswered == 0 ? 0 : Double(correctAnswers) / Double(cardsAnswered)
    }

    init(records: [ScoreRecord]) {
        sessions = records.count
        cardsAnswered = records.reduce(0) { $0 + $1.total }
        correctAnswers = records.reduce(0) { $0 + $1.correct }
        bestAccuracy = records.map(\.accuracy).max() ?? 0
    }
}

/// Where finished study sessions are kept. The backend has no score API yet, so the
/// implementation is local; swap it for a remote one later without touching view models.
protocol ScoreRepository: Sendable {
    func save(_ record: ScoreRecord) async
    /// Newest first.
    func records() async -> [ScoreRecord]
}
