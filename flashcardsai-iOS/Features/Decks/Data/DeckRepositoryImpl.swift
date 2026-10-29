import Foundation

/// Uses the *authorized* client: token attach + refresh-and-retry happen below.
struct DeckRepositoryImpl: DeckRepository {
    /// Gemini generation is slow; the default 60s request timeout is too tight.
    static let createDeckTimeout: TimeInterval = 90

    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchDecks() async throws -> [DeckSummary] {
        let dtos: [DeckSummaryDTO] = try await client.send(Endpoint(path: "/api/decks", method: .get))
        return dtos.map { $0.toDomain() }
    }

    func fetchDeck(id: Int) async throws -> Deck {
        let dto: DeckDTO = try await client.send(Endpoint(path: "/api/decks/\(id)", method: .get))
        return dto.toDomain()
    }

    func createDeck(topic: String, difficulty: Difficulty) async throws -> Deck {
        let endpoint = try Endpoint.json(path: "/api/decks",
                                         body: CreateDeckRequestDTO(topic: topic, difficulty: difficulty),
                                         timeout: Self.createDeckTimeout)
        let dto: DeckDTO = try await client.send(endpoint)
        return dto.toDomain()
    }

    func deleteDeck(id: Int) async throws {
        _ = try await client.send(Endpoint(path: "/api/decks/\(id)", method: .delete))
    }
}
