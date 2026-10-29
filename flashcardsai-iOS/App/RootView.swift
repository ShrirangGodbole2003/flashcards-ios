import SwiftUI

/// Decides what the user sees from the authentication state.
struct RootView: View {
    let container: AppContainer
    @Bindable var sessionStore: SessionStore
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        Group {
            switch sessionStore.state {
            case .launching:
                LaunchView()
            case .signedOut:
                AuthFlowView(authRepository: container.authRepository,
                             serverName: AppConfig.isDebugBuild ? container.config.apiBaseURL.absoluteString : nil,
                             onAuthenticated: sessionStore.didAuthenticate)
            case .signedIn(let user):
                MainTabView(user: user,
                            deckRepository: container.deckRepository,
                            scoreRepository: container.makeScoreRepository(userID: user.id),
                            snapshotPublisher: container.deckSnapshotPublisher,
                            studyActivityController: container.studyActivityController,
                            reminderScheduler: container.reminderScheduler,
                            environmentName: AppConfig.isDebugBuild ? container.config.apiBaseURL.host() : nil,
                            onLogout: { await sessionStore.logout() })
                    .id(user.id)
            case .launchFailed(let message):
                LaunchFailedView(message: message) { Task { await sessionStore.restore() } }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sessionStore.state)
        // Only when a signed-in session ends (logout / expiry). Not on launch: a link that
        // opened the app while signed out must survive until the user signs in.
        .onChange(of: sessionStore.state) { old, new in
            if case .signedIn = old, case .signedOut = new { router.reset() }
        }
        .task { await sessionStore.restore() }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Theme.Spacing.l) {
                AuthHeader(title: "Flashcards AI", subtitle: "")
                ProgressView().tint(Theme.Colors.primary)
            }
        }
    }
}

private struct LaunchFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Theme.Spacing.xl) {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't open your account", message: message)
                Button("Try again", action: retry)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.Spacing.xxl)
            }
        }
    }
}

/// Shown instead of the app when API_BASE_URL is missing or invalid (developer error).
struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            AppBackground()
            EmptyStateView(systemImage: "gearshape.trianglebadge.exclamationmark",
                           title: "Configuration error",
                           message: message)
        }
    }
}
