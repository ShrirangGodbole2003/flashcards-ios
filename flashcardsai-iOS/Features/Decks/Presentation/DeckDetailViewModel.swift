import Foundation
import Observation

@MainActor
@Observable
final class DeckDetailViewModel {
    let summary: DeckSummary
    private(set) var deck: Deck?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let repository: DeckRepository

    init(summary: DeckSummary, repository: DeckRepository) {
        self.summary = summary
        self.repository = repository
    }

    var countsByType: [(type: CardType, count: Int)] {
        guard let deck else { return [] }
        return [CardType.qa, .mcq, .trueFalse].compactMap { type in
            let count = deck.cards.filter { $0.type == type }.count
            return count > 0 ? (type, count) : nil
        }
    }

    func load() async {
        guard deck == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            deck = try await repository.fetchDeck(id: summary.id)
        } catch is CancellationError {
            return
        } catch APIError.sessionExpired {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }
}
