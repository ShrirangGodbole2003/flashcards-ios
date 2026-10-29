import Foundation
import Observation

/// App-wide authentication state. The root view switches on `state`.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case launching
        case signedOut
        case signedIn(AuthUser)
        /// Stored credentials exist but the server could not be reached.
        case launchFailed(String)
    }

    private(set) var state: State = .launching

    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private let snapshotPublisher: DeckSnapshotPublishing
    @ObservationIgnored private let studyActivityController: StudyActivityControlling
    @ObservationIgnored private let reminderScheduler: ReminderScheduling
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    init(authRepository: AuthRepository,
         events: AsyncStream<SessionEvent>,
         snapshotPublisher: DeckSnapshotPublishing = NoopDeckSnapshotPublisher(),
         studyActivityController: StudyActivityControlling = NoopStudyActivityController(),
         reminderScheduler: ReminderScheduling = NoopReminderScheduler()) {
        self.authRepository = authRepository
        self.snapshotPublisher = snapshotPublisher
        self.studyActivityController = studyActivityController
        self.reminderScheduler = reminderScheduler
        // The TokenManager announces when the refresh token was rejected anywhere in the app.
        eventsTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    deinit {
        eventsTask?.cancel()
    }

    /// Launch: turn a stored refresh token into a live session (or land on the login screen).
    func restore() async {
        state = .launching
        // Any study activity still showing belongs to a previous launch: this process has no session.
        studyActivityController.endAll()
        do {
            if let user = try await authRepository.restoreSession() {
                state = .signedIn(user)
            } else {
                signOut()
            }
        } catch APIError.sessionExpired {
            signOut()
        } catch is CancellationError {
            return
        } catch {
            state = .launchFailed(error.userMessage)
        }
    }

    func didAuthenticate(_ user: AuthUser) {
        state = .signedIn(user)
    }

    func logout() async {
        await authRepository.logout()
        signOut()
    }

    /// Every path to `.signedOut` goes through here so the widget and Lock Screen never keep a previous account's data (reminders included).
    private func signOut() {
        snapshotPublisher.clear()
        studyActivityController.endAll()
        reminderScheduler.cancelAll()   // reminders name decks of the account that just left
        state = .signedOut
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .expired:
            signOut()
        }
    }
}
