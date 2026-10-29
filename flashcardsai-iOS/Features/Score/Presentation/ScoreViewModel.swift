import Foundation
import Observation

@MainActor
@Observable
final class ScoreViewModel {
    private(set) var records: [ScoreRecord] = []
    private(set) var stats = ScoreStats(records: [])
    private(set) var hasLoaded = false

    @ObservationIgnored private let repository: ScoreRepository

    init(repository: ScoreRepository) {
        self.repository = repository
    }

    func load() async {
        records = await repository.records()
        stats = ScoreStats(records: records)
        hasLoaded = true
    }
}
