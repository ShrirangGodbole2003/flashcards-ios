import Foundation
import WidgetKit

/// Writes the newest decks into the App Group and asks WidgetKit to redraw the widget.
@MainActor
struct WidgetSnapshotPublisher: DeckSnapshotPublishing {
    /// Enough for the large widget (the small one shows only the first).
    static let maxDecks = 5

    private let store: WidgetSnapshotStoring
    private let reload: () -> Void

    init(store: WidgetSnapshotStoring = AppGroupSnapshotStore(),
         reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reload = reload
    }

    func publish(decks: [DeckSummary]) {
        let widgetDecks = decks.prefix(Self.maxDecks).map {
            WidgetDeck(id: $0.id,
                       topic: $0.topic,
                       difficultyName: $0.difficulty.displayName,
                       cardCount: $0.cardCount)
        }
        // The list is refreshed often; only redraw the widget when something it shows changed.
        guard store.load()?.decks != widgetDecks else { return }
        store.save(WidgetSnapshot(decks: widgetDecks, updatedAt: Date()))
        reload()
    }

    func clear() {
        guard store.load() != nil else { return }
        store.clear()
        reload()
    }
}
