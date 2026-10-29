# Networking layer: how it works, why it is built this way, and what to improve

Source: `flashcardsai-iOS/Core/Networking/*`, `Core/Security/TokenManager.swift`, the repositories in `Features/*/Data`.
References look like `File.swift:line`. Companion docs: `docs/AuthLayer.md` (login trace), `docs/TokenManager.md` (token lifecycle), backend `DOCUMENTATION.md` §8 (the API contract).

**Contents**
1. Architecture at a glance
2. Component reference (what each piece is and why it exists)
3. Request lifecycles
4. Design decisions and the reasoning behind each
5. How networking layers are generally built on iOS
6. Interview cheat sheet
7. How to add a new API call
8. Testing seams
9. **TODO / betterments** (weak or missing points)

---

## 1. Architecture at a glance

```
 ViewModel ──▶ Repository (protocol, Domain)
                   │ implemented by
                   ▼
              RepositoryImpl (Data)  ── builds Endpoint, decodes DTOs, maps to domain models
                   │ depends on the PROTOCOL
                   ▼
              HTTPClient  ◀── protocol: send(Endpoint) async throws -> Data
              ┌────┴──────────────────────────────┐
              │                                   │
   AuthorizedHTTPClient (decorator)       URLSessionHTTPClient (transport)
   adds Bearer token                      builds URLRequest, calls URLSession,
   401 → refresh → retry once             maps status codes / errors to APIError
              │                                   ▲
              └────────── wraps ──────────────────┘
              │
        TokenProviding (protocol) ──▶ TokenManager (actor)

 Supporting types:  Endpoint (request as data) · APIError + ProblemDetail (errors) · JSONCoding (encode/decode/dates)
```

Wiring (all in `AppContainer.swift:22-29`):
- `plainClient` = `URLSessionHTTPClient`: no tokens.
- `authorizedClient` = `AuthorizedHTTPClient(base: plainClient, tokens: tokenManager)`.
- Auth calls (`/api/auth/*`) use `plainClient`. Everything protected (decks…) uses `authorizedClient`.

---

## 2. Component reference

### 2.1 `Endpoint`: the request described as data (`Endpoint.swift:4`)
- A `struct`, not a protocol: it holds `path`, `method` (`get/post/delete`), `body` (`Data?`), `requiresAuth`, `timeout`, `headers`.
- `Endpoint.json(path:method:body:requiresAuth:timeout:)` (`:33`) encodes any `Encodable` into the body.
- `addingHeader(_:_:)` (`:45`) returns a *copy* with one more header (never mutates).
- **Why data and not a function per call:** a value can be inspected, logged, copied, retried and decorated by any layer. `AuthorizedHTTPClient` relies on this: it re-sends the *same* endpoint with a different `Authorization` header.
- `requiresAuth` (`:15`) is the per-call switch for "attach a token?". Defaults to `true`; auth endpoints set `false`.

### 2.2 `HTTPClient`: the transport contract (`HTTPClient.swift:5`)
- One requirement: `send(_ endpoint:) async throws -> Data` (the bytes of a 2xx response, empty for 204; throws `APIError` otherwise).
- A protocol extension (`:9-17`) adds `send<Response: Decodable>(_:as:)`: sends, then decodes with `JSONCoding.makeDecoder()`, mapping decode failures to `APIError.decoding`.
- **Why split bytes and decoding:** transport implementations stay tiny and generic. Decoding is written once, for every client.
- **Why a protocol:** the thing that actually talks to the network is swappable (real, authorized, test double, preview fake).

### 2.3 `URLSessionHTTPClient`: the real transport (`URLSessionHTTPClient.swift:4`)
- The **only** type that imports `URLSession` concepts. It knows nothing about tokens, users or the backend's business rules.
- `send` (`:13-35`): `makeRequest` → `session.data(for:)` → map the outcome:

| Outcome | Becomes | Line |
|---|---|---|
| 2xx | returns `Data` | `:28` |
| 401 | `APIError.unauthorized(ProblemDetail?)` | `:30` |
| other status | `APIError.http(status:problem:)` | `:32` |
| `URLError` | `APIError.transport(code)` | `:22` |
| `URLError.cancelled` | `CancellationError` | `:21` |
| response isn't HTTP | `APIError.invalidResponse` | `:25` |

- `makeRequest` (`:37-55`): joins `baseURL` + path (`:39`), sets method, `Accept: application/json`, `Content-Type` only when there is a body, the endpoint's timeout if set, then custom headers.
- `decodeProblem` (`:57`): best-effort decode of the backend's RFC 9457 body, so the server's own message reaches the user.
- **Why map errors here:** this is the lowest layer that sees the raw `URLError`/status code. Normalising there means every layer above handles *one* error type.
- **Why `CancellationError` for `.cancelled`:** Swift concurrency's own cancellation type, so view models can ignore it (`catch is CancellationError`) without an error banner.

### 2.4 `AuthorizedHTTPClient`: auth as a decorator (`AuthorizedHTTPClient.swift:7`)
- Same interface as `HTTPClient`, and *wraps* another one (`base`).
- `send` (`:16-27`):
  1. `requiresAuth == false` → pass straight through (`:17`).
  2. `tokens.validAccessToken()` (`:19`), refreshing first if the cached one is near expiry.
  3. Send with `Authorization: Bearer …` (`:21`).
  4. If it throws `.unauthorized` → `tokens.refreshAccessToken(afterRejecting:)` (`:24`) → send **once more** with the fresh token (`:25`). A second 401 propagates; **no loops**.
- **Why a decorator:** auth is a cross-cutting concern. Putting it in the transport would couple `URLSession` code to tokens; putting it in repositories would repeat it everywhere. Decorating keeps both clean and lets the *same* transport serve public and protected calls.
- **Why it depends on `TokenProviding`, not `TokenManager`:** the two methods it needs (interface segregation); it can be tested with a 5-line stub.

### 2.5 `APIError` and `ProblemDetail` (`APIError.swift:3`, `ProblemDetail.swift:5`)
- `APIError` cases: `invalidURL`, `invalidResponse`, `transport(URLError.Code)`, `unauthorized`, `http(status:problem:)`, `decoding`, `sessionExpired`, `storage`.
- `ProblemDetail` mirrors the backend's RFC 9457 body: `title, status, detail, instance, errors` (`errors` = field → message for 400s).
- `fieldErrors` (`APIError.swift:24`) exposes per-field messages for forms; `isConnectivityIssue` (`:26`) groups "no internet / timeout / can't connect".
- `Error.userMessage` (`:61`) → `LocalizedError.errorDescription` (`:37`) returns text that is safe to show. **All wording is in this one place.**
- **Why one error enum:** the UI has exactly one thing to switch on. No `URLError` or status codes leak above the transport.

### 2.6 `JSONCoding` (`JSONCoding.swift`)
- `makeEncoder()` / `makeDecoder()` are the single JSON configuration.
- The decoder uses a custom date strategy backed by `ISO8601DateParser` (`:27`): the backend prints fractional seconds with 0/3/6/9 digits and `ISO8601DateFormatter` is unreliable beyond milliseconds, so the fraction is normalised to milliseconds first.

### 2.7 Repositories: the typed API (e.g. `DeckRepositoryImpl.swift`)
- They build an `Endpoint` (`:15`, `:20`, `:25-27`, `:33`), call `client.send`, receive **DTOs**, and convert them to **domain models** (`toDomain()`).
- `createDeck` overrides the timeout to 90 s (`:6`, `:27`) because Gemini generation is slow; everything else uses the default.
- **Why DTO → domain:** the backend's JSON shape is its contract, not the app's model. Changing a field name touches the DTO only.

### 2.8 `TokenManager` (summary; full detail in `docs/TokenManager.md`)
- Actor that owns the access token (memory) and refresh token (Keychain), refreshes **single-flight**, and signals `.expired` through an `AsyncStream` when the session is truly dead.

### 2.9 Session configuration (`AppContainer.swift:44-49`)
- `URLSessionConfiguration.default` with `requestCachePolicy = .reloadIgnoringLocalCacheData`: authenticated responses are never served from the local HTTP cache.
- `waitsForConnectivity = false`: fail fast when offline, so the UI can say so immediately instead of hanging.

---

## 3. Request lifecycles

### 3.1 Public call (login / register / refresh / logout)
```
AuthRemoteDataSource ─▶ Endpoint(requiresAuth: false) ─▶ URLSessionHTTPClient ─▶ backend
```
- No token, no `AuthorizedHTTPClient`. A 401 means "wrong credentials" and is returned to the caller as `.unauthorized(problem)`.

### 3.2 Protected call, token valid
```
DeckRepositoryImpl.fetchDecks
 └ AuthorizedHTTPClient.send
    ├ tokens.validAccessToken()                (cached and > 30 s left → returned immediately)
    └ URLSessionHTTPClient.send  [Authorization: Bearer …]  ─▶ 200 ─▶ Data
 └ HTTPClient.send<…> decodes [DeckSummaryDTO] ─▶ repository maps to [DeckSummary]
```

### 3.3 Protected call, access token expired
```
AuthorizedHTTPClient.send
 ├ validAccessToken() ─▶ near expiry ─▶ TokenManager refreshes (single flight) ─▶ new token   (proactive)
 └ OR: send ─▶ 401 ─▶ refreshAccessToken(afterRejecting: old) ─▶ send again with the new token  (reactive, once)
```
- Ten concurrent requests → **one** refresh (see `docs/TokenManager.md`).
- Refresh rejected (401) → `APIError.sessionExpired` is thrown to the caller **and** `.expired` is emitted → `SessionStore` shows the login screen.
- Refresh failed because of the network → the original error propagates; the session is kept.

### 3.4 Failure path
- The error is thrown at the lowest layer that knows about it (`URLSessionHTTPClient`, `HTTPClient` decoding, `TokenManager`) and **unwinds unchanged** through every `try await` until a view model catches it and shows `error.userMessage`. No middle layer rewrites or swallows errors.

### 3.5 Cancellation
- Cancelling the Swift `Task` reaches `URLSession`, which throws `URLError.cancelled` → converted to `CancellationError` (`URLSessionHTTPClient.swift:21`) → view models `return` silently.

---

## 4. Design decisions and the reasoning

| # | Decision | Reason | Alternative considered / trade-off |
|---|---|---|---|
| 1 | **Plain `URLSession` + async/await**, no library | The needs are small (JSON, bearer auth, one retry). No dependency to keep updated, and the refresh behaviour is explicit, not hidden in an interceptor | Alamofire/Moya bring interceptors, multipart, reachability. Worth adopting if those needs appear |
| 2 | **`HTTPClient` is a protocol** | Swap the transport for tests/previews; compose behaviour by wrapping | A concrete `APIClient` class is simpler but couples every caller to `URLSession` |
| 3 | **Decorator for auth** (`AuthorizedHTTPClient`) | Cross-cutting concern kept out of both the transport and the repositories | An interceptor array (Alamofire style) is more general; this app needs exactly one |
| 4 | **`Endpoint` is a value (`struct`)** | Inspectable, copyable, retryable; enables the "same request, new header" retry | A function per call is shorter but can't be retried or decorated |
| 5 | **Bytes first, decode in an extension** | Transport stays generic; decoding in one place | Having the client return `T` directly is convenient but duplicates decode/error code |
| 6 | **One `APIError` enum, normalised at the transport** | UI has one error vocabulary; no `URLError` leaks upward | Passing raw errors is less code but pushes interpretation into every screen |
| 7 | **Server `ProblemDetail` surfaced to users** | The backend already produces consistent, user-safe messages | Hard-coding client strings per status would drift from the server |
| 8 | **Auth endpoints use the plain client + `requiresAuth: false`** | A 401 there means bad credentials, not expiry, so there is no refresh loop; and no Bearer is sent (contract) | Single client for everything needs special cases for `/auth` |
| 9 | **Retry exactly once, only on 401** | Handles expiry/clock skew; never loops; never replays a request that may have had side effects for other errors | Generic retry/backoff is a separate, riskier feature (see TODO) |
| 10 | **Refresh logic lives in `TokenManager` (actor), not in the client** | One owner for token state; concurrent callers share one refresh (backend revokes the session on refresh-token reuse) | Per-request refresh in the client would race |
| 11 | **DTOs separate from domain models** | Backend contract changes stay in `Data` | Using DTOs in views is fewer types but couples UI to JSON |
| 12 | **Per-endpoint timeout** (`createDeck` 90 s, logout 5 s) | Gemini is slow; logout must not block the UI | One global timeout is either too short or too long for some calls |
| 13 | **No HTTP caching** | Authenticated, per-user data; stale or cross-account cache hits would be a privacy bug | Caching would help read-heavy public data, not applicable now |
| 14 | **`waitsForConnectivity = false`** | Offline is reported immediately | `true` would hang requests until a connection appears |
| 15 | **Base URL from env/Info.plist, https required in release** | No hard-coded hosts; a plain-HTTP release build is refused at startup | Hard-coding is simpler but blocks staging/production switching |

---

## 5. How networking layers are generally built on iOS

**The ladder (simple → heavy):**
1. Raw `URLSession` calls inside view models: quick, but duplicated, untestable, inconsistent errors.
2. A thin `APIClient` with a generic `request<T: Decodable>`: the usual starting point.
3. **A protocol-oriented layer** (request/endpoint type + transport protocol + decorators/interceptors + typed errors): *where this app is.*
4. **A library:**
   - **Alamofire:** `Session`, `RequestInterceptor` (adapt + retry), response validation, multipart/upload, reachability.
   - **Moya:** a typed target (`TargetType`/enum of endpoints) on top of Alamofire.
   - **Apollo** (GraphQL).
5. **Generated clients:** Apple's swift-openapi-generator (or similar) turns an OpenAPI spec into a typed client so the contract can't drift.

**Features a mature layer usually has:** auth interceptor + single-flight refresh · retry with exponential backoff (idempotent calls) · logging with secrets redacted · reachability (`NWPathMonitor`) · caching/ETags · certificate pinning · multipart & background uploads · request de-duplication · pagination helpers · environment switching · request IDs · test seams (`URLProtocol` stub or mock client).

**Where `URLProtocol` fits:** a `URLProtocol` subclass registered on a `URLSessionConfiguration` intercepts requests inside `URLSession`. It's how tests stub the network without changing production code (`NetworkingTests.swift` does this).

---

## 6. Interview cheat sheet

**30-second answer**
- "I separated *what to call* (`Endpoint`, a value) from *how to send it* (`HTTPClient`, a protocol) and from *what it means* (repositories mapping DTOs to domain models). Auth is a decorator around the transport that attaches the token and, on a 401, refreshes once and retries. Errors are normalised to one `APIError` at the lowest layer. Token state lives in one actor so concurrent refreshes collapse into a single call. It's plain `URLSession` with async/await and no third-party dependencies."

**Likely questions**
- *Why not Alamofire?* Needs are small, refresh logic stays visible, one less dependency. I'd adopt it for multipart uploads, reachability or complex interceptor chains.
- *Why a protocol for the client?* Testing and composition: the transport is replaceable and auth is added by wrapping it.
- *Why a decorator?* Auth is cross-cutting; the transport and repositories shouldn't know about tokens.
- *What if 10 requests get 401 together?* They all call `refreshAccessToken`; the actor lets exactly one refresh run and the others reuse its result.
- *Why not retry on every error?* Retrying non-idempotent calls (e.g. POST create deck) can duplicate work. Only 401 is retried, because a 401 means the server rejected the call before acting on it.
- *Where are errors turned into messages?* Created in the transport, wording in `APIError`, displayed by view models via `userMessage`.
- *How do you test it?* Mock `HTTPClient` for repositories; `URLProtocol` stub for the transport; stub `TokenProviding`/`TokenRefresher` for auth.
- *How does cancellation work?* Task cancellation → `URLSession` throws `.cancelled` → mapped to `CancellationError` → ignored by UI.
- *How would you scale it?* Typed endpoints (or OpenAPI-generated), retry/backoff for idempotent calls, logging/metrics, richer responses (headers), pagination, certificate pinning.
- *What are the limits?* See §9.

---

## 7. How to add a new API call

Example: `GET /api/decks/{id}/cards` (hypothetical).

1. **Domain:** add the method to the repository **protocol** (`DeckRepository`) with domain types.
2. **DTO:** add a `Decodable` DTO in `Features/Decks/Data/DeckDTOs.swift` with `toDomain()`.
3. **Repository impl:**
   ```swift
   func fetchCards(deckID: Int) async throws -> [Card] {
       let dtos: [CardDTO] = try await client.send(Endpoint(path: "/api/decks/\(deckID)/cards", method: .get))
       return dtos.map { $0.toDomain() }
   }
   ```
   - Body? Use `try Endpoint.json(path:body:)`.
   - Slow call? pass `timeout:`.
   - Public endpoint? pass `requiresAuth: false` and make sure the repo is built on the **plain** client.
4. **View model:** call the protocol method, catch `CancellationError` silently, show `error.userMessage` otherwise.
5. **Preview/test fakes:** add the method to `PreviewDeckRepository` and mocks.
6. **Docs:** update the backend contract note and the change log.
No change is needed in `HTTPClient`, `AuthorizedHTTPClient` or `TokenManager`.

---

## 8. Testing seams

| Layer | Substitute with | Existing coverage |
|---|---|---|
| Repository ← view model | `Mock…Repository` / `Preview…Repository` | view-model tests |
| `HTTPClient` ← repository | `RecordingHTTPClient` (test double) | used by `AuthorizedHTTPClient` tests |
| `URLSessionHTTPClient` | `StubURLProtocol` on an ephemeral session | request building, 200/204/401/400/500, offline, decoding |
| `AuthorizedHTTPClient` | `StubTokenProvider` + `RecordingHTTPClient` | bearer attach, one retry, no loop, no retry for non-401 |
| `TokenManager` | `InMemorySecureStore` + `StubRefresher` + `TestClock` | expiry, rotation, single flight, failure handling |

(All under `flashcardsai-iOSTests/`; per the current workflow no new tests are added until asked.)

---

## 9. TODO / betterments (weak or missing points)

Priority: **P1** = do before release or when the first need appears · **P2** = worthwhile soon · **P3** = nice to have.

| # | Gap | Why it matters | Suggested fix | P |
|---|---|---|---|---|
| 1 | **No query parameters.** `Endpoint` has only `path`; `URL.appending(path:)` is for path segments, so a `?page=2` placed in `path` is not a reliable way to send a query | Any list/search/pagination API needs it | Add `queryItems: [URLQueryItem]` to `Endpoint` and apply via `URLComponents` in `makeRequest` | P1 |
| 2 | **No retry/backoff for transient failures** (502, 503, timeouts) | One Gemini hiccup or flaky mobile connection fails the whole action | Add a `RetryingHTTPClient` decorator: exponential backoff + jitter, honour `Retry-After`, **only for idempotent methods** (GET/DELETE) or with an `Idempotency-Key` for POST (a retried create-deck could otherwise duplicate decks) | P1 |
| 3 | **Only GET/POST/DELETE** | Updating a resource (PUT/PATCH) can't be expressed | Add `put`, `patch` to `Endpoint.Method` | P1 |
| 4 | **`HTTPClient` returns only `Data`** (no status code or headers) | Can't read `Retry-After`, `ETag`, `Link`/pagination headers, rate-limit headers | Return an `HTTPResponse { data, statusCode, headers }` and keep a convenience that returns `Data` | P2 |
| 5 | **Timeouts are idle timeouts.** `timeoutInterval` limits the time without data, not the total duration; `timeoutIntervalForResource` is left at the system default (days) | A stalled-but-trickling request could hang for a very long time | Set `timeoutIntervalForResource` (e.g. 120 s) in `makeURLSession()` | P2 |
| 6 | **No logging or metrics** | Hard to diagnose "it failed on my phone" | `LoggingHTTPClient` decorator using `os.Logger`: method, path, status, duration; **never** log bodies, `Authorization`, passwords or tokens. Add `X-Request-ID` so client and server logs correlate | P2 |
| 7 | **Stringly-typed paths** scattered in repositories (`"/api/decks/\(id)"`) | Typos, hard to find all uses, hard to see the API surface | Group them as endpoint factories (`enum DeckAPI { static func detail(id:) -> Endpoint }`, Moya-style) | P2 |
| 8 | **No reachability monitoring** | Can't show an offline banner, or pause/retry automatically when the network returns | `NWPathMonitor` wrapped in an `AsyncStream<Bool>` service; use it for UI hints and retry triggers | P2 |
| 9 | **No deck-generation resilience.** The request is a foreground `URLSession` call; if the user leaves the app it is suspended after ~30 s | Long Gemini calls get cut off | Short term: `beginBackgroundTask`; proper fix needs a backend job API (202 + job id, poll or push) and a background `URLSession` or push | P2 |
| 10 | **No certificate pinning / ATS review** | Higher assurance against MITM, mostly relevant for sensitive apps | Pin via `URLSessionDelegate` only if the threat model justifies the operational cost (key rotation) | P3 |
| 11 | **No multipart/upload support** | Needed for avatar upload, file import | `Endpoint` body variants (`.multipart`), upload tasks, background session for large files | P3 |
| 12 | **No request de-duplication or response caching for reads** | Repeated identical GETs (pull-to-refresh spam) | Coalesce in-flight identical GETs (dictionary of `Task`s keyed by URL); ETag/If-None-Match when the backend supports it | P3 |
| 13 | **403/429 are not specially handled** | A rate-limit response should back off, a 403 should say "not allowed" | Map in `APIError` (`.forbidden`, `.rateLimited(retryAfter:)`); backend currently has no rate limit | P3 |
| 14 | **`APIError.transport` keeps only the `URLError.Code`** | Loses detail (e.g. which TLS error) for diagnostics | Add the underlying error to the log line (not to user text) | P3 |
| 15 | **Hand-written DTOs and paths can drift from the backend** | Silent contract breaks | Generate the client from an OpenAPI spec (needs the backend to publish one, e.g. springdoc) | P3 |
| 16 | **Single environment config** | No staging vs production switch beyond the env var | Per-configuration `.xcconfig` (see `DOCUMENTATION.md` §4) | P2 |
| 17 | **Other refresh-related items** | See `docs/TokenManager.md` §7: single listener on the events stream, extensions needing a refresh strategy, no tests for the hardening | — | P2 |

---

## 10. Quick index

| I want to… | Look at |
|---|---|
| See how a request is built and sent | §2.3, `URLSessionHTTPClient.swift:37-55` |
| See how auth is attached and retried | §2.4, `AuthorizedHTTPClient.swift:16-27` |
| Understand which error becomes which message | §2.5, `docs/AuthLayer.md` §7.10 |
| Add an endpoint | §7 |
| Prepare for an interview | §4 and §6 |
| Know what to improve next | §9 |
