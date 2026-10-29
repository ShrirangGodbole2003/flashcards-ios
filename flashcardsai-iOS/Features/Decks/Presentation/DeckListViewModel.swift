import Foundation
import Observation

@MainActor
@Observable
final class DeckListViewModel {
    private(set) var decks: [DeckSummary] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let repository: DeckRepository
    @ObservationIgnored private let snapshotPublisher: DeckSnapshotPublishing

    init(repository: DeckRepository,
         snapshotPublisher: DeckSnapshotPublishing = NoopDeckSnapshotPublisher()) {
        self.repository = repository
        self.snapshotPublisher = snapshotPublisher
    }

    /// Initial load: spinner only while there is nothing to show yet.
    func load() async {
        guard !hasLoaded else { return }
        await fetch()
    }

    /// Pull-to-refresh: keeps the current list visible.
    func refresh() async {
        await fetch()
    }

    /// Adds a freshly generated deck without waiting for a round trip.
    func insert(_ summary: DeckSummary) {
        decks.removeAll { $0.id == summary.id }
        decks.insert(summary, at: 0)
        snapshotPublisher.publish(decks: decks)
    }

    private func fetch() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            decks = try await repository.fetchDecks().sorted { $0.createdAt > $1.createdAt }
            hasLoaded = true
            snapshotPublisher.publish(decks: decks)
        } catch is CancellationError {
            return
        } catch APIError.sessionExpired {
            return          // SessionStore is already routing to the login screen
        } catch {
            errorMessage = error.userMessage
        }
    }
}
