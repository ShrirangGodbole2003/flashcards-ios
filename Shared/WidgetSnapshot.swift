import Foundation

/// One deck as the widget needs it: just enough to draw a button and build a deep link.
struct WidgetDeck: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let topic: String
    let difficultyName: String
    let cardCount: Int
}

/// What the app hands to the widget. The widget runs in another process with no access to the
/// app's memory or Keychain, so this small value, stored in the App Group, is its only data.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    let decks: [WidgetDeck]
    let updatedAt: Date
}

protocol WidgetSnapshotStoring: Sendable {
    func load() -> WidgetSnapshot?
    func save(_ snapshot: WidgetSnapshot)
    func clear()
}

/// Stores the snapshot as JSON in the App Group's UserDefaults. Safe to call from both processes.
struct AppGroupSnapshotStore: WidgetSnapshotStoring {
    private static let key = "widget.snapshot.v1"
    private let suiteName: String

    init(suiteName: String = AppGroup.identifier) {
        self.suiteName = suiteName
    }

    func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    func clear() {
        defaults?.removeObject(forKey: Self.key)
    }

    // nil when the App Group isn't configured for this target: everything then no-ops.
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
}
