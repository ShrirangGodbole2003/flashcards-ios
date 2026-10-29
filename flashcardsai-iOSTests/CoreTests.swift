import Foundation
import Testing
@testable import flashcardsai_iOS

// MARK: Date parsing (backend sends UTC instants with 0/3/6/9 fractional digits)

struct DateParsingTests {
    private let base = ISO8601DateFormatter().date(from: "2026-10-20T17:55:46Z")!

    @Test(arguments: [
        ("2026-10-20T17:55:46Z", 0.0),
        ("2026-10-20T17:55:46.1Z", 0.1),
        ("2026-10-20T17:55:46.104Z", 0.104),
        ("2026-10-20T17:55:46.104058Z", 0.104),
        ("2026-10-20T17:55:46.104058123Z", 0.104),
        ("2026-10-20T17:55:46.104058+00:00", 0.104),
    ])
    func parsesAllFractionLengths(string: String, fraction: Double) throws {
        let date = try #require(ISO8601DateParser.parse(string))
        #expect(abs(date.timeIntervalSince(base) - fraction) < 0.0015)
    }

    @Test(arguments: ["", "not a date", "2026-10-20", "2026-10-20T17:55:46.Z"])
    func rejectsGarbage(string: String) {
        #expect(ISO8601DateParser.parse(string) == nil)
    }

    @Test func decodesInsideJSON() throws {
        struct Wrapper: Decodable { let createdAt: Date }
        let json = #"{"createdAt":"2026-10-20T17:55:46.104058Z"}"#
        let decoded = try JSONCoding.makeDecoder().decode(Wrapper.self, from: Data(json.utf8))
        #expect(abs(decoded.createdAt.timeIntervalSince(base) - 0.104) < 0.0015)
    }
}

// MARK: Config

struct AppConfigTests {
    @Test func environmentVariableWins() throws {
        let config = try AppConfig.load(environment: ["API_BASE_URL": "https://api.example.com"],
                                        infoDictionary: ["API_BASE_URL": "https://other.example.com"],
                                        isDebugBuild: false)
        #expect(config.apiBaseURL.absoluteString == "https://api.example.com")
    }

    @Test func fallsBackToInfoPlist() throws {
        let config = try AppConfig.load(environment: [:],
                                        infoDictionary: ["API_BASE_URL": "https://plist.example.com"],
                                        isDebugBuild: false)
        #expect(config.apiBaseURL.host() == "plist.example.com")
    }

    @Test func debugBuildsDefaultToLocalhost() throws {
        let config = try AppConfig.load(environment: [:], infoDictionary: nil, isDebugBuild: true)
        #expect(config.apiBaseURL.absoluteString == "http://localhost:8080")
    }

    @Test func releaseWithoutValueThrows() {
        #expect(throws: AppConfig.ConfigError.missingBaseURL) {
            try AppConfig.load(environment: [:], infoDictionary: nil, isDebugBuild: false)
        }
    }

    @Test func releaseRejectsPlainHTTP() {
        #expect(throws: AppConfig.ConfigError.insecureBaseURL("http://api.example.com")) {
            try AppConfig.load(environment: ["API_BASE_URL": "http://api.example.com"],
                               infoDictionary: nil, isDebugBuild: false)
        }
    }

    @Test(arguments: ["not a url", "ftp://example.com", "https://"])
    func invalidValuesThrow(value: String) {
        #expect(throws: AppConfig.ConfigError.self) {
            try AppConfig.load(environment: ["API_BASE_URL": value], infoDictionary: nil, isDebugBuild: true)
        }
    }

    @Test func blankEnvironmentValueIsIgnored() throws {
        let config = try AppConfig.load(environment: ["API_BASE_URL": "   "], infoDictionary: nil, isDebugBuild: true)
        #expect(config.apiBaseURL.host() == "localhost")
    }
}

// MARK: Credentials validation

struct CredentialsValidatorTests {
    @Test(arguments: ["a@b.co", "alice@example.com", "first.last+tag@sub.example.org"])
    func acceptsValidEmails(email: String) {
        #expect(CredentialsValidator.emailError(email) == nil)
    }

    @Test(arguments: ["", "   ", "abc", "a@b", "@example.com", "a@@b.com", "a b@c.com", "a@.com", "a@b."])
    func rejectsInvalidEmails(email: String) {
        #expect(CredentialsValidator.emailError(email) != nil)
    }

    @Test func emailIsTrimmedBeforeChecking() {
        #expect(CredentialsValidator.emailError("  a@b.co  ") == nil)
        #expect(CredentialsValidator.normalizedEmail("  a@b.co \n") == "a@b.co")
    }

    @Test func passwordRules() {
        #expect(CredentialsValidator.passwordError("") != nil)
        #expect(CredentialsValidator.passwordError("short") != nil)
        #expect(CredentialsValidator.passwordError("12345678") == nil)
        #expect(CredentialsValidator.passwordError(String(repeating: "a", count: 72)) == nil)
        #expect(CredentialsValidator.passwordError(String(repeating: "a", count: 73)) != nil)
        // 40 two-byte characters = 80 bytes: under 72 characters but over the BCrypt byte limit
        #expect(CredentialsValidator.passwordError(String(repeating: "é", count: 40)) != nil)
    }

    @Test func confirmationMustMatch() {
        #expect(CredentialsValidator.confirmationError(password: "abc", confirmation: "abc") == nil)
        #expect(CredentialsValidator.confirmationError(password: "abc", confirmation: "abd") != nil)
    }
}

// MARK: Contract tests: decode the exact JSON shapes documented by the backend

struct BackendContractTests {
    @Test func authResponse() throws {
        let json = """
        {"accessToken":"eyJ.x.y","refreshToken":"q3j8","tokenType":"Bearer","expiresIn":900,
         "user":{"id":1,"email":"alice@example.com"}}
        """
        let dto = try JSONCoding.makeDecoder().decode(AuthResponseDTO.self, from: Data(json.utf8))
        let received = Date(timeIntervalSince1970: 1_000)
        let session = dto.toSession(receivedAt: received)
        #expect(session.tokens.accessToken == "eyJ.x.y")
        #expect(session.tokens.refreshToken == "q3j8")
        #expect(session.tokens.accessTokenExpiresAt == received.addingTimeInterval(900))
        #expect(session.user == AuthUser(id: 1, email: "alice@example.com"))
    }

    @Test func deckWithAllCardTypesAndNulls() throws {
        let json = """
        {"id":1,"topic":"Spring Boot","difficulty":"INTERMEDIATE","cards":[
          {"id":1,"type":"QA","question":"q","answer":"a","options":null,"correctIndex":null,"explanation":"e","hint":"h"},
          {"id":2,"type":"MCQ","question":"q","answer":"server.port","options":["a","server.port","c","d"],"correctIndex":1,"explanation":null,"hint":null},
          {"id":3,"type":"TRUE_FALSE","question":"q","answer":"True","options":null,"correctIndex":null,"explanation":"e","hint":"h"}
        ]}
        """
        let deck = try JSONCoding.makeDecoder().decode(DeckDTO.self, from: Data(json.utf8)).toDomain()
        #expect(deck.difficulty == .intermediate)
        #expect(deck.cards.map(\.type) == [.qa, .mcq, .trueFalse])
        #expect(deck.cards[0].options.isEmpty)
        #expect(deck.cards[1].options.count == 4)
        #expect(deck.cards[1].correctIndex == 1)
        #expect(deck.cards[1].explanation == nil)
    }

    @Test func deckSummaryList() throws {
        let json = """
        [{"id":12,"topic":"Spring Boot","difficulty":"BEGINNER","cardCount":6,"createdAt":"2026-10-20T15:35:11.123456Z"}]
        """
        let list = try JSONCoding.makeDecoder().decode([DeckSummaryDTO].self, from: Data(json.utf8))
        #expect(list.first?.toDomain().cardCount == 6)
    }

    @Test func problemDetailWithFieldErrors() throws {
        let json = """
        {"title":"Validation Failed","status":400,"detail":"Request validation failed.",
         "instance":"/api/auth/register","errors":{"email":"must be a well-formed email address"}}
        """
        let problem = try JSONCoding.makeDecoder().decode(ProblemDetail.self, from: Data(json.utf8))
        #expect(problem.status == 400)
        #expect(problem.errors?["email"] == "must be a well-formed email address")
    }

    @Test func allBackendEnumValuesAreKnown() {
        #expect(Difficulty.allCases.map(\.rawValue) == ["BEGINNER", "INTERMEDIATE", "ADVANCED"])
        #expect(CardType(rawValue: "QA") == .qa)
        #expect(CardType(rawValue: "MCQ") == .mcq)
        #expect(CardType(rawValue: "TRUE_FALSE") == .trueFalse)
    }
}
