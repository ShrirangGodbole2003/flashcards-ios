import Foundation

/// Stores scores on-device, namespaced per user so accounts never see each other's history.
actor UserDefaultsScoreRepository: ScoreRepository {
    static let maxStoredRecords = 200

    private let key: String
    private let defaults: UserDefaults

    init(userID: Int, defaults: UserDefaults = .standard) {
        self.key = "scores.v1.user.\(userID)"
        self.defaults = defaults
    }

    func save(_ record: ScoreRecord) {
        var all = load()
        all.insert(record, at: 0)
        if all.count > Self.maxStoredRecords { all.removeLast(all.count - Self.maxStoredRecords) }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }

    func records() -> [ScoreRecord] {
        load()
    }

    private func load() -> [ScoreRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ScoreRecord].self, from: data)) ?? []
    }
}
