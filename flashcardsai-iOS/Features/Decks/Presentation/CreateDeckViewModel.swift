import Foundation
import Observation

@MainActor
@Observable
final class CreateDeckViewModel {
    static let maxTopicLength = 100
    static let suggestions = ["Swift concurrency", "Docker basics", "World War II",
                              "Organic chemistry", "Spanish verbs", "Personal finance"]

    var topic = ""
    var difficulty: Difficulty = .beginner

    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var topicError: String?

    @ObservationIgnored private let repository: DeckRepository

    init(repository: DeckRepository) {
        self.repository = repository
    }

    var trimmedTopic: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Returns the new deck on success, `nil` on failure (the error is published).
    func generate() async -> Deck? {
        guard !isGenerating else { return nil }
        errorMessage = nil
        topicError = nil

        if trimmedTopic.isEmpty {
            topicError = "Enter a topic to study."
            return nil
        }
        if trimmedTopic.count > Self.maxTopicLength {
            topicError = "Keep the topic under \(Self.maxTopicLength) characters."
            return nil
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await repository.createDeck(topic: trimmedTopic, difficulty: difficulty)
        } catch is CancellationError {
            return nil
        } catch {
            if let apiError = error as? APIError, let message = apiError.fieldErrors["topic"] {
                topicError = message
            } else {
                errorMessage = error.userMessage
            }
            return nil
        }
    }
}
