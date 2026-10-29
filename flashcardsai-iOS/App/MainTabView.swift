import SwiftUI

enum AppTab: Hashable {
    case decks, score, profile
}

/// Signed-in shell. Each tab owns its own NavigationStack so tabs keep their own history.
/// `.id(user.id)` on the caller guarantees a clean slate when a different account signs in.
struct MainTabView: View {
    let user: AuthUser
    let deckRepository: DeckRepository
    let scoreRepository: ScoreRepository
    var snapshotPublisher: DeckSnapshotPublishing = NoopDeckSnapshotPublisher()
    var studyActivityController: StudyActivityControlling = NoopStudyActivityController()
    var reminderScheduler: ReminderScheduling = NoopReminderScheduler()
    let environmentName: String?
    let onLogout: () async -> Void

    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            DecksTabView(repository: deckRepository,
                         scoreRepository: scoreRepository,
                         snapshotPublisher: snapshotPublisher,
                         activityController: studyActivityController,
                         reminderScheduler: reminderScheduler)
                .tabItem { Label("Decks", systemImage: "rectangle.stack.fill") }
                .tag(AppTab.decks)

            ScoreView(viewModel: ScoreViewModel(repository: scoreRepository))
                .tabItem { Label("Score", systemImage: "chart.bar.fill") }
                .tag(AppTab.score)

            ProfileView(user: user, environmentName: environmentName, onLogout: onLogout)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
        .tint(Theme.Colors.primary)
        .alert("Couldn't open link",
               isPresented: Binding(get: { router.notice != nil },
                                    set: { if !$0 { router.dismissNotice() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.notice ?? "")
        }
    }
}

#if DEBUG
#Preview("Main tabs") {
    MainTabView(user: PreviewData.user,
                deckRepository: PreviewDeckRepository(),
                scoreRepository: PreviewScoreRepository(),
                environmentName: "localhost",
                onLogout: {})
        .environment(DeepLinkRouter())
}
#endif
