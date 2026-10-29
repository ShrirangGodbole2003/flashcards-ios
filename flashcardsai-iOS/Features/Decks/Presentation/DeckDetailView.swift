import SwiftUI

struct DeckDetailView: View {
    // Owned by the view (like StudyView): the navigation destination closure builds a new
    // view model on every parent re-render, and a plain/@Bindable property would swap to that
    // empty one while `.task` (tied to the view's identity) never ran again.
    @State private var viewModel: DeckDetailViewModel
    @State private var reminder: DeckReminderViewModel
    let onStart: (Deck) -> Void

    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: DeckDetailViewModel,
         reminderScheduler: ReminderScheduling = NoopReminderScheduler(),
         onStart: @escaping (Deck) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onStart = onStart
        _reminder = State(initialValue: DeckReminderViewModel(summary: viewModel.summary, scheduler: reminderScheduler))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                    Button("Try again") { Task { await viewModel.load() } }
                        .buttonStyle(SecondaryButtonStyle())
                }

                if let deck = viewModel.deck {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(viewModel.countsByType, id: \.type) { item in
                            StatTile(value: "\(item.count)", label: item.type.displayName, systemImage: item.type.systemImage)
                        }
                    }

                    Button { onStart(deck) } label: {
                        Label("Start studying", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    DeckReminderSection(viewModel: reminder)

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Cards in this deck")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        ForEach(Array(deck.cards.enumerated()), id: \.element.id) { index, card in
                            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                Text("\(index + 1)")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.primary)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.Colors.surfaceTint, in: Circle())
                                Text(card.question)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: card.type.systemImage)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .accessibilityLabel(card.type.displayName)
                            }
                            .padding(Theme.Spacing.m)
                            .cardSurface(cornerRadius: 16)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView().tint(Theme.Colors.primary).frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(AppBackground())
        .navigationTitle(viewModel.summary.topic)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .task { await reminder.load() }
        // Back from Settings (permission) or a reminder that has fired meanwhile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminder.load() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(viewModel.summary.topic)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.s) {
                Badge(text: viewModel.summary.difficulty.displayName, tint: viewModel.summary.difficulty.tint)
                Badge(text: "\(viewModel.deck?.cards.count ?? viewModel.summary.cardCount) cards",
                      systemImage: "rectangle.stack")
            }
        }
    }
}
