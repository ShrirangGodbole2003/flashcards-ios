import WidgetKit
import SwiftUI

// MARK: - Timeline

struct DeckEntry: TimelineEntry {
    let date: Date
    /// Newest first. Empty when the user is signed out or has no decks.
    let decks: [WidgetDeck]
}

/// Reads what the app saved in the App Group. The widget never calls the API: it has no access to
/// the app's tokens. `.never` because the app asks WidgetKit to reload whenever the decks change.
struct Provider: TimelineProvider {
    private let store: WidgetSnapshotStoring = AppGroupSnapshotStore()

    func placeholder(in context: Context) -> DeckEntry {
        DeckEntry(date: .now, decks: WidgetDeck.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeckEntry) -> Void) {
        // The widget gallery preview should always look populated.
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeckEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> DeckEntry {
        DeckEntry(date: .now, decks: store.load()?.decks ?? [])
    }
}

// MARK: - Widget

struct FlashcardsWidget: Widget {
    let kind = "FlashcardsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FlashcardsWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Theme.Colors.backgroundTop, Theme.Colors.background],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Study a deck")
        .description("Jump straight into your latest deck.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - Views

struct FlashcardsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeckEntry

    var body: some View {
        switch family {
        case .systemLarge: DeckListWidgetView(decks: entry.decks)
        default: SmallDeckView(deck: entry.decks.first)
        }
    }
}

/// One tap target for the whole widget: opens the newest deck.
private struct SmallDeckView: View {
    let deck: WidgetDeck?

    var body: some View {
        if let deck {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Study")
                Spacer(minLength: 0)
                Text(deck.topic)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Text(deck.detailText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                StartPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(DeepLink.deck(id: deck.id).url)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the deck")
        } else {
            EmptyDeckView()
        }
    }
}

/// Up to five decks, each row opens its own deck. Taps outside a row open the deck list.
/// Large, not medium: a medium widget is too short for a header plus several rows.
private struct DeckListWidgetView: View {
    let decks: [WidgetDeck]

    var body: some View {
        if decks.isEmpty {
            EmptyDeckView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Study a deck")
                VStack(spacing: 8) {
                    ForEach(decks) { deck in
                        Link(destination: DeepLink.deck(id: deck.id).url) {
                            DeckRow(deck: deck)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(DeepLink.decks.url)
        }
    }
}

private struct DeckRow: View {
    let deck: WidgetDeck

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Colors.onPrimary)
                .frame(width: 26, height: 26)
                .background(Theme.Colors.primary, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.topic)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(deck.detailText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Study \(deck.topic), \(deck.detailText)")
    }
}

private struct EmptyDeckView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Flashcards AI")
            Spacer(minLength: 0)
            Text("No decks yet")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Open the app to create or sign in.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(DeepLink.decks.url)
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.stack.fill")
            Text(title)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.primary)
    }
}

/// Looks like a button; a widget can't run actions, the tap is the widget's link.
private struct StartPill: View {
    var body: some View {
        Text("Start")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.onPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Theme.Colors.primary, in: Capsule())
    }
}

// MARK: - Helpers

private extension WidgetDeck {
    var detailText: String {
        "\(difficultyName) · \(cardCount) \(cardCount == 1 ? "card" : "cards")"
    }

    static let samples = [
        WidgetDeck(id: 1, topic: "Swift Concurrency", difficultyName: "Intermediate", cardCount: 12),
        WidgetDeck(id: 2, topic: "Spanish Basics", difficultyName: "Beginner", cardCount: 10),
        WidgetDeck(id: 3, topic: "World Capitals", difficultyName: "Advanced", cardCount: 15),
        WidgetDeck(id: 4, topic: "Human Anatomy", difficultyName: "Intermediate", cardCount: 8),
        WidgetDeck(id: 5, topic: "Music Theory", difficultyName: "Beginner", cardCount: 1),
    ]
}

#Preview("Small", as: .systemSmall) {
    FlashcardsWidget()
} timeline: {
    DeckEntry(date: .now, decks: WidgetDeck.samples)
    DeckEntry(date: .now, decks: [])
}

#Preview("Large", as: .systemLarge) {
    FlashcardsWidget()
} timeline: {
    DeckEntry(date: .now, decks: WidgetDeck.samples)
    DeckEntry(date: .now, decks: [])
}
