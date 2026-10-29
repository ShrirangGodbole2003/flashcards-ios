import Foundation

/// Composition root: the only place that knows concrete types and wires them together.
/// Everything else receives protocols.
///
///   URLSessionHTTPClient (plain) --> AuthRemoteDataSource --(TokenRefresher)--> TokenManager
///                      \                                                           |
///                       \--> AuthorizedHTTPClient (adds Bearer, refresh+retry) <----/
///                                      \--> DeckRepositoryImpl
@MainActor
final class AppContainer {
    let config: AppConfig
    let tokenManager: TokenManager
    let authRepository: AuthRepository
    let deckRepository: DeckRepository
    let deckSnapshotPublisher: DeckSnapshotPublishing
    let studyActivityController: StudyActivityControlling
    let reminderScheduler: ReminderScheduling

    init(config: AppConfig,
         secureStore: SecureStore = KeychainSecureStore(),
         urlSession: URLSession = AppContainer.makeURLSession()) {
        self.config = config

        let plainClient = URLSessionHTTPClient(baseURL: config.apiBaseURL, session: urlSession)
        let authRemote = AuthRemoteDataSource(client: plainClient)
        let tokenManager = TokenManager(store: secureStore, refresher: authRemote)
        let authorizedClient = AuthorizedHTTPClient(base: plainClient, tokens: tokenManager)

        self.tokenManager = tokenManager
        self.authRepository = AuthRepositoryImpl(remote: authRemote, tokenManager: tokenManager)
        self.deckRepository = DeckRepositoryImpl(client: authorizedClient)
        self.deckSnapshotPublisher = WidgetSnapshotPublisher()
        self.studyActivityController = LiveStudyActivityController()
        self.reminderScheduler = UserNotificationReminderScheduler()
    }

    static func live() throws -> AppContainer {
        AppContainer(config: try AppConfig.load(debugOverride: DebugServerOverride.read()))
    }

    func makeSessionStore() -> SessionStore {
        SessionStore(authRepository: authRepository,
                     events: tokenManager.events,
                     snapshotPublisher: deckSnapshotPublisher,
                     studyActivityController: studyActivityController,
                     reminderScheduler: reminderScheduler)
    }

    func makeScoreRepository(userID: Int) -> ScoreRepository {
        UserDefaultsScoreRepository(userID: userID)
    }

    nonisolated static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData   // never serve stale/authorised data from cache
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}
