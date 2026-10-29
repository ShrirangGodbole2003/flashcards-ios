import Foundation

protocol DeckRepository: Sendable {
    func fetchDecks() async throws -> [DeckSummary]
    func fetchDeck(id: Int) async throws -> Deck
    /// Generates cards with Gemini on the backend; can take several seconds.
    func createDeck(topic: String, difficulty: Difficulty) async throws -> Deck
    func deleteDeck(id: Int) async throws
}
