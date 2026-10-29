import Foundation

struct CreateDeckRequestDTO: Encodable {
    let topic: String
    let difficulty: Difficulty
}

struct CardDTO: Decodable {
    let id: Int
    let type: CardType
    let question: String
    let answer: String
    let options: [String]?
    let correctIndex: Int?
    let explanation: String?
    let hint: String?

    func toDomain() -> Card {
        Card(id: id, type: type, question: question, answer: answer,
             options: options ?? [], correctIndex: correctIndex,
             explanation: explanation, hint: hint)
    }
}

struct DeckDTO: Decodable {
    let id: Int
    let topic: String
    let difficulty: Difficulty
    let cards: [CardDTO]

    func toDomain() -> Deck {
        Deck(id: id, topic: topic, difficulty: difficulty, cards: cards.map { $0.toDomain() })
    }
}

struct DeckSummaryDTO: Decodable {
    let id: Int
    let topic: String
    let difficulty: Difficulty
    let cardCount: Int
    let createdAt: Date

    func toDomain() -> DeckSummary {
        DeckSummary(id: id, topic: topic, difficulty: difficulty, cardCount: cardCount, createdAt: createdAt)
    }
}
