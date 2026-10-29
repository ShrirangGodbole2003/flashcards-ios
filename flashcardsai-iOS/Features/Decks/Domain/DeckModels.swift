import Foundation

/// Raw values are the exact strings the backend uses.
enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner = "BEGINNER"
    case intermediate = "INTERMEDIATE"
    case advanced = "ADVANCED"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
}

enum CardType: String, Codable, Sendable {
    case qa = "QA"
    case mcq = "MCQ"
    case trueFalse = "TRUE_FALSE"

    var displayName: String {
        switch self {
        case .qa: return "Question"
        case .mcq: return "Multiple choice"
        case .trueFalse: return "True / False"
        }
    }

    var systemImage: String {
        switch self {
        case .qa: return "text.bubble"
        case .mcq: return "list.bullet.circle"
        case .trueFalse: return "checkmark.circle.trianglebadge.exclamationmark"
        }
    }
}

struct Card: Identifiable, Hashable, Sendable {
    let id: Int
    let type: CardType
    let question: String
    let answer: String
    /// Empty unless `type == .mcq` (exactly 4 entries).
    let options: [String]
    let correctIndex: Int?
    let explanation: String?
    let hint: String?
}

struct Deck: Identifiable, Hashable, Sendable {
    let id: Int
    let topic: String
    let difficulty: Difficulty
    let cards: [Card]

    var summary: DeckSummary {
        DeckSummary(id: id, topic: topic, difficulty: difficulty, cardCount: cards.count, createdAt: Date())
    }
}

struct DeckSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let topic: String
    let difficulty: Difficulty
    let cardCount: Int
    let createdAt: Date
}
