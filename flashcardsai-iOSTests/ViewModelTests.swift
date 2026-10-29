import Foundation
import Testing
@testable import flashcardsai_iOS

// MARK: Login / Register

@MainActor
struct AuthViewModelTests {
    @Test func loginRejectsInvalidInputWithoutCallingTheServer() async {
        let repo = MockAuthRepository()
        let viewModel = LoginViewModel(authRepository: repo) { _ in }
        viewModel.email = "nope"

        await viewModel.submit()

        #expect(viewModel.emailError != nil)
        #expect(viewModel.passwordError != nil)
        #expect(repo.loginCalls.isEmpty)
    }

    @Test func loginTrimsTheEmailAndReportsTheUser() async {
        let repo = MockAuthRepository()
        var authenticated: AuthUser?
        let viewModel = LoginViewModel(authRepository: repo) { authenticated = $0 }
        viewModel.email = "  alice@example.com "
        viewModel.password = "correct-horse"

        await viewModel.submit()

        #expect(repo.loginCalls.first?.email == "alice@example.com")
        #expect(authenticated == AuthUser(id: 1, email: "a@b.com"))
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test func wrongCredentialsShowTheServerMessage() async {
        let repo = MockAuthRepository()
        repo.loginResult = .failure(APIError.unauthorized(
            ProblemDetail(title: "Invalid Credentials", status: 401, detail: "Invalid email or password.", instance: nil, errors: nil)))
        var called = false
        let viewModel = LoginViewModel(authRepository: repo) { _ in called = true }
        viewModel.email = "alice@example.com"
        viewModel.password = "wrong-password"

        await viewModel.submit()

        #expect(viewModel.errorMessage == "Invalid email or password.")
        #expect(!called)
    }

    @Test func offlineLoginShowsAConnectionMessage() async {
        let repo = MockAuthRepository()
        repo.loginResult = .failure(APIError.transport(.notConnectedToInternet))
        let viewModel = LoginViewModel(authRepository: repo) { _ in }
        viewModel.email = "alice@example.com"
        viewModel.password = "whatever1"

        await viewModel.submit()

        #expect(viewModel.errorMessage?.contains("reach the server") == true)
    }

    @Test func registerValidatesAllFieldsLocally() async {
        let repo = MockAuthRepository()
        let viewModel = RegisterViewModel(authRepository: repo) { _ in }
        viewModel.email = "alice@example.com"
        viewModel.password = "short"
        viewModel.confirmation = "different"

        await viewModel.submit()

        #expect(viewModel.emailError == nil)
        #expect(viewModel.passwordError != nil)
        #expect(viewModel.confirmationError != nil)
        #expect(repo.registerCalls.isEmpty)
    }

    @Test func registerMapsConflictToTheEmailField() async {
        let repo = MockAuthRepository()
        repo.registerResult = .failure(APIError.http(status: 409, problem: nil))
        let viewModel = RegisterViewModel(authRepository: repo) { _ in }
        viewModel.email = "alice@example.com"
        viewModel.password = "correct-horse"
        viewModel.confirmation = "correct-horse"

        await viewModel.submit()

        #expect(viewModel.emailError == "An account with this email already exists.")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func registerMapsServerFieldErrors() async {
        let repo = MockAuthRepository()
        let problem = ProblemDetail(title: "Validation Failed", status: 400, detail: nil, instance: nil,
                                    errors: ["password": "size must be between 8 and 72"])
        repo.registerResult = .failure(APIError.http(status: 400, problem: problem))
        let viewModel = RegisterViewModel(authRepository: repo) { _ in }
        viewModel.email = "alice@example.com"
        viewModel.password = "correct-horse"
        viewModel.confirmation = "correct-horse"

        await viewModel.submit()

        #expect(viewModel.passwordError == "size must be between 8 and 72")
    }

    @Test func successfulRegistrationSignsIn() async {
        let repo = MockAuthRepository()
        var authenticated: AuthUser?
        let viewModel = RegisterViewModel(authRepository: repo) { authenticated = $0 }
        viewModel.email = "alice@example.com"
        viewModel.password = "correct-horse"
        viewModel.confirmation = "correct-horse"

        await viewModel.submit()

        #expect(authenticated != nil)
        #expect(repo.registerCalls.count == 1)
    }
}

// MARK: Session store

@MainActor
struct SessionStoreTests {
    private func makeStore(_ repo: MockAuthRepository) -> (SessionStore, AsyncStream<SessionEvent>.Continuation) {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        return (SessionStore(authRepository: repo, events: stream), continuation)
    }

    @Test func restoreWithAStoredSessionSignsIn() async {
        let repo = MockAuthRepository()
        repo.restoreResult = .success(AuthUser(id: 4, email: "x@y.com"))
        let (store, _) = makeStore(repo)

        await store.restore()

        #expect(store.state == .signedIn(AuthUser(id: 4, email: "x@y.com")))
    }

    @Test func restoreWithNothingStoredShowsLogin() async {
        let (store, _) = makeStore(MockAuthRepository())
        await store.restore()
        #expect(store.state == .signedOut)
    }

    @Test func restoreRejectedByServerShowsLogin() async {
        let repo = MockAuthRepository()
        repo.restoreResult = .failure(APIError.sessionExpired)
        let (store, _) = makeStore(repo)
        await store.restore()
        #expect(store.state == .signedOut)
    }

    @Test func restoreWhileOfflineOffersRetryInsteadOfLoggingOut() async {
        let repo = MockAuthRepository()
        repo.restoreResult = .failure(APIError.transport(.notConnectedToInternet))
        let (store, _) = makeStore(repo)

        await store.restore()

        guard case .launchFailed = store.state else { Issue.record("state was \(store.state)"); return }
    }

    @Test func expiredEventFromTheTokenManagerSignsOut() async {
        let repo = MockAuthRepository()
        repo.restoreResult = .success(AuthUser(id: 1, email: "a@b.com"))
        let (store, continuation) = makeStore(repo)
        await store.restore()
        #expect(store.state != .signedOut)

        continuation.yield(.expired)

        for _ in 0..<100 where store.state != .signedOut { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(store.state == .signedOut)
    }

    @Test func logoutCallsTheRepositoryAndSignsOut() async {
        let repo = MockAuthRepository()
        repo.restoreResult = .success(AuthUser(id: 1, email: "a@b.com"))
        let (store, _) = makeStore(repo)
        await store.restore()

        await store.logout()

        #expect(repo.logoutCount == 1)
        #expect(store.state == .signedOut)
    }

    @Test func didAuthenticateSignsIn() {
        let (store, _) = makeStore(MockAuthRepository())
        store.didAuthenticate(AuthUser(id: 9, email: "n@e.w"))
        #expect(store.state == .signedIn(AuthUser(id: 9, email: "n@e.w")))
    }
}

// MARK: Decks

@MainActor
struct DeckViewModelTests {
    private func summary(_ id: Int, daysAgo: Double) -> DeckSummary {
        DeckSummary(id: id, topic: "T\(id)", difficulty: .beginner, cardCount: 6,
                    createdAt: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func deckListLoadsNewestFirst() async {
        let repo = MockDeckRepository()
        repo.decksResult = .success([summary(1, daysAgo: 3), summary(2, daysAgo: 1), summary(3, daysAgo: 2)])
        let viewModel = DeckListViewModel(repository: repo)

        await viewModel.load()

        #expect(viewModel.decks.map(\.id) == [2, 3, 1])
        #expect(viewModel.hasLoaded)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deckListShowsErrorsWithoutDroppingExistingDecks() async {
        let repo = MockDeckRepository()
        repo.decksResult = .success([summary(1, daysAgo: 1)])
        let viewModel = DeckListViewModel(repository: repo)
        await viewModel.load()

        repo.decksResult = .failure(APIError.transport(.notConnectedToInternet))
        await viewModel.refresh()

        #expect(viewModel.decks.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func insertPutsTheNewDeckFirstWithoutDuplicates() async {
        let repo = MockDeckRepository()
        repo.decksResult = .success([summary(1, daysAgo: 1)])
        let viewModel = DeckListViewModel(repository: repo)
        await viewModel.load()

        viewModel.insert(summary(2, daysAgo: 0))
        viewModel.insert(summary(2, daysAgo: 0))

        #expect(viewModel.decks.map(\.id) == [2, 1])
    }

    @Test func createDeckValidatesTopic() async {
        let repo = MockDeckRepository()
        let viewModel = CreateDeckViewModel(repository: repo)

        viewModel.topic = "   "
        #expect(await viewModel.generate() == nil)
        #expect(viewModel.topicError != nil)

        viewModel.topic = String(repeating: "x", count: 101)
        #expect(await viewModel.generate() == nil)
        #expect(viewModel.topicError != nil)

        #expect(repo.createCalls.isEmpty)
    }

    @Test func createDeckSendsTrimmedTopicAndDifficulty() async {
        let repo = MockDeckRepository()
        let viewModel = CreateDeckViewModel(repository: repo)
        viewModel.topic = "  Swift concurrency \n"
        viewModel.difficulty = .advanced

        let deck = await viewModel.generate()

        #expect(deck != nil)
        #expect(repo.createCalls.first?.topic == "Swift concurrency")
        #expect(repo.createCalls.first?.difficulty == .advanced)
        #expect(!viewModel.isGenerating)
    }

    @Test func createDeckSurfacesGeminiFailure() async {
        let repo = MockDeckRepository()
        let problem = ProblemDetail(title: "Card Generation Failed", status: 502,
                                    detail: "Card generation failed. Please try again later.", instance: nil, errors: nil)
        repo.createResult = .failure(APIError.http(status: 502, problem: problem))
        let viewModel = CreateDeckViewModel(repository: repo)
        viewModel.topic = "Swift"

        let deck = await viewModel.generate()

        #expect(deck == nil)
        #expect(viewModel.errorMessage == "Card generation failed. Please try again later.")
    }

    @Test func detailCountsCardsByType() async {
        let repo = MockDeckRepository()
        let viewModel = DeckDetailViewModel(summary: TestData.deck().summary, repository: repo)
        await viewModel.load()

        #expect(viewModel.countsByType.map(\.count) == [1, 1, 1])
        #expect(viewModel.countsByType.map(\.type) == [.qa, .mcq, .trueFalse])
    }
}

// MARK: Study + scores

@MainActor
struct StudyViewModelTests {
    private func makeDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func finishingASessionSavesExactlyOneScore() async {
        let scores = UserDefaultsScoreRepository(userID: 1, defaults: makeDefaults())
        let viewModel = StudyViewModel(deck: TestData.deck(cards: [TestData.mcq(correctIndex: 1)]), scoreRepository: scores)

        viewModel.selectOption(1)
        viewModel.next()
        viewModel.next()            // extra call after finishing must not save twice

        for _ in 0..<100 where await scores.records().isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        let records = await scores.records()
        #expect(records.count == 1)
        #expect(records.first?.correct == 1)
        #expect(records.first?.total == 1)
    }

    @Test func hintResetsOnNextCard() {
        let viewModel = StudyViewModel(deck: TestData.deck(cards: [TestData.mcq(id: 1), TestData.mcq(id: 2)]),
                                       scoreRepository: UserDefaultsScoreRepository(userID: 1, defaults: makeDefaults()))
        viewModel.toggleHint()
        #expect(viewModel.isHintVisible)
        viewModel.selectOption(1)
        viewModel.next()
        #expect(!viewModel.isHintVisible)
    }

    @Test func restartAllowsASecondScoreToBeSaved() async {
        let scores = UserDefaultsScoreRepository(userID: 1, defaults: makeDefaults())
        let viewModel = StudyViewModel(deck: TestData.deck(cards: [TestData.trueFalse()]), scoreRepository: scores)

        viewModel.answerTrueFalse(true); viewModel.next()
        viewModel.restart()
        viewModel.answerTrueFalse(false); viewModel.next()

        for _ in 0..<100 where await scores.records().count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await scores.records().count == 2)
    }
}

struct ScoreRepositoryTests {
    private func makeDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func record(_ correct: Int, total: Int = 6, minutesAgo: Double = 0) -> ScoreRecord {
        ScoreRecord(id: UUID(), deckID: 1, deckTopic: "T", difficulty: .beginner,
                    correct: correct, total: total, date: Date().addingTimeInterval(-minutesAgo * 60))
    }

    @Test func recordsAreNewestFirst() async {
        let repo = UserDefaultsScoreRepository(userID: 1, defaults: makeDefaults())
        let first = record(1), second = record(2)
        await repo.save(first)
        await repo.save(second)
        #expect(await repo.records().map(\.id) == [second.id, first.id])
    }

    @Test func accountsNeverSeeEachOthersScores() async {
        let defaults = makeDefaults()
        let alice = UserDefaultsScoreRepository(userID: 1, defaults: defaults)
        let bob = UserDefaultsScoreRepository(userID: 2, defaults: defaults)

        await alice.save(record(5))

        #expect(await alice.records().count == 1)
        #expect(await bob.records().isEmpty)
    }

    @Test func historyIsCapped() async {
        let repo = UserDefaultsScoreRepository(userID: 1, defaults: makeDefaults())
        for _ in 0..<(UserDefaultsScoreRepository.maxStoredRecords + 10) { await repo.save(record(3)) }
        #expect(await repo.records().count == UserDefaultsScoreRepository.maxStoredRecords)
    }

    @Test func statsAggregateRecords() {
        let stats = ScoreStats(records: [record(6), record(3), record(0)])
        #expect(stats.sessions == 3)
        #expect(stats.cardsAnswered == 18)
        #expect(stats.correctAnswers == 9)
        #expect(stats.averageAccuracy == 0.5)
        #expect(stats.bestAccuracy == 1)
    }

    @Test func statsOfNothingAreZero() {
        let stats = ScoreStats(records: [])
        #expect(stats.averageAccuracy == 0)
        #expect(stats.bestAccuracy == 0)
    }
}
