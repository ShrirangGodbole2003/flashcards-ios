import SwiftUI

/// Navigation destinations inside the Decks tab. Using a typed path keeps the door
/// open for deep links (push `.detail` / `.study` from a URL or notification).
enum DecksRoute: Hashable {
    case detail(DeckSummary)
    case study(Deck)
}

struct DecksTabView: View {
    private let repository: DeckRepository
    private let scoreRepository: ScoreRepository
    private let activityController: StudyActivityControlling
    private let reminderScheduler: ReminderScheduling

    @State private var listViewModel: DeckListViewModel
    @Environment(DeepLinkRouter.self) private var router
    @State private var isPresentingCreate = false

    init(repository: DeckRepository,
         scoreRepository: ScoreRepository,
         snapshotPublisher: DeckSnapshotPublishing = NoopDeckSnapshotPublisher(),
         activityController: StudyActivityControlling = NoopStudyActivityController(),
         reminderScheduler: ReminderScheduling = NoopReminderScheduler()) {
        self.repository = repository
        self.scoreRepository = scoreRepository
        self.activityController = activityController
        self.reminderScheduler = reminderScheduler
        _listViewModel = State(initialValue: DeckListViewModel(repository: repository,
                                                               snapshotPublisher: snapshotPublisher))
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.decksPath) {
            DeckListView(viewModel: listViewModel,
                         onSelect: { router.decksPath.append(.detail($0)) },
                         onCreate: { isPresentingCreate = true })
                .navigationDestination(for: DecksRoute.self) { route in
                    switch route {
                    case .detail(let summary):
                        DeckDetailView(
                            viewModel: DeckDetailViewModel(summary: summary, repository: repository),
                            reminderScheduler: reminderScheduler,
                            onStart: { router.decksPath.append(.study($0)) })
                        // A deep link can replace the detail at the same stack position with another
                        // deck; a new identity gives it fresh state (view model, reminder) and a new `.task`.
                        .id(summary.id)
                    case .study(let deck):
                        StudyView(viewModel: StudyViewModel(deck: deck,
                                                            scoreRepository: scoreRepository,
                                                            activityController: activityController),
                                  onClose: {
                            router.decksPath.removeLast() })
                    }
                }
        }
        // Deep links: try when one arrives, and again once the deck list has loaded.
        .onAppear(perform: applyPendingLink)
        .onChange(of: router.pendingLink) { applyPendingLink() }
        .onChange(of: listViewModel.hasLoaded) { applyPendingLink() }
        .sheet(isPresented: $isPresentingCreate) {
            CreateDeckView(viewModel: CreateDeckViewModel(repository: repository)) { deck in
                isPresentingCreate = false
                listViewModel.insert(deck.summary)
                router.decksPath = [.detail(deck.summary)]
            }
        }
    }

    /// nil tells the router the list isn't available yet, so a deck link waits instead of failing.
    private func applyPendingLink() {
        router.applyPending(decks: listViewModel.hasLoaded ? listViewModel.decks : nil)
    }
}

#if DEBUG
#Preview("Decks tab") {
    DecksTabView(repository: PreviewDeckRepository(), scoreRepository: PreviewScoreRepository())
        .environment(DeepLinkRouter())
}
#endif
