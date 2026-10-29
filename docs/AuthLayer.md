# Auth layer: every function, every frame, and why it is built this way

Read this next to the code. Every reference looks like `File.swift:line` (paths are under `flashcardsai-iOS/`).
Line numbers match the code at the time of writing. If a file changes, re-check them.

Related docs: `docs/TokenManager.md` (token lifecycle in depth), `DOCUMENTATION.md` (whole app), backend `DOCUMENTATION.md` §4 and §8 (the server side of this contract).

**Contents**
1. The map: who is who
2. Why it is structured this way (protocols, impls, remote, DTOs…)
3. Before anyone logs in: how the objects get wired
4. **The login trace: from typing to the tabs, function by function**
5. The same trace as a call stack
6. What the backend does during that one call
7. Failure traces (the "error frames")
8. Register: what differs
9. App launch / session restore trace
10. Logout trace
11. After login: how the access token is used
12. Session-expiry trace (the `AsyncStream` path)
13. Design Q&A
14. Honest weak spots
15. Quick index

---

## 1. The map: who is who

| Layer | File | Kind | Job in one line |
|---|---|---|---|
| Presentation | `Features/Auth/Presentation/LoginView.swift` | SwiftUI `View` | Draws the form, forwards taps |
| Presentation | `Features/Auth/Presentation/LoginViewModel.swift` | `@Observable @MainActor class` | Holds form state, validates, calls the repository, turns errors into text |
| Presentation | `Features/Auth/Presentation/RegisterView(Model).swift` | same | Same for sign-up |
| Presentation | `Features/Auth/Presentation/AuthFlowView.swift` | `View` | Signed-out container: creates the view models, hosts the `NavigationStack` |
| Domain | `Features/Auth/Domain/AuthRepository.swift` | **protocol** | What the app can ask of "accounts": register, login, restore, logout |
| Domain | `Features/Auth/Domain/CredentialsValidator.swift` | `enum` of pure functions | Client-side email/password rules |
| Data | `Features/Auth/Data/AuthRepositoryImpl.swift` | `struct` implementing the protocol | Orchestrates: call the server, then hand tokens to the token manager |
| Data | `Features/Auth/Data/AuthRemoteDataSource.swift` | `struct` | Knows the `/api/auth/*` URLs and JSON shapes; nothing else |
| Data | `Features/Auth/Data/AuthDTOs.swift` | `struct`s | Wire-format types and their mapping to domain types |
| Core | `Core/Networking/Endpoint.swift` | `struct` | A description of one API call (path, method, body, flags) |
| Core | `Core/Networking/HTTPClient.swift` | **protocol** + extension | "Send an endpoint, give me bytes (or decode them)" |
| Core | `Core/Networking/URLSessionHTTPClient.swift` | `struct` implementing `HTTPClient` | The only place that touches `URLSession` |
| Core | `Core/Networking/AuthorizedHTTPClient.swift` | `struct` implementing `HTTPClient` | Adds Bearer token + refresh-and-retry (**not used by login**) |
| Core | `Core/Networking/APIError.swift`, `ProblemDetail.swift` | `enum` / `struct` | One error vocabulary for the whole app |
| Core | `Core/Networking/JSONCoding.swift` | `enum` | JSON encoder/decoder config, date parsing |
| Core | `Core/Security/AuthModels.swift` | `struct`s | `AuthUser`, `AuthTokens`, `AuthSession` (domain values) |
| Core | `Core/Security/TokenManager.swift` | **`actor`** | Owns the tokens: memory + Keychain, refresh, session-expired signal |
| Core | `Core/Security/SecureStore.swift` | **protocol** + Keychain impl | Reads/writes secrets |
| App | `App/SessionStore.swift` | `@Observable @MainActor class` | The app-wide "am I logged in?" state |
| App | `App/RootView.swift` | `View` | Shows login, tabs, or a retry screen depending on that state |
| App | `App/flashcardsai_iOSApp.swift` | `@main App` | Builds the container at launch |
| Core | `Core/DI/AppContainer.swift` | `@MainActor final class` | The **only** place that creates concrete objects and connects them |

Two vocabularies are used on purpose:

| Domain values (used by the app) | Wire values (DTOs, used only in `Data`) |
|---|---|
| `AuthUser`, `AuthTokens`, `AuthSession` | `UserDTO`, `AuthResponseDTO`, `CredentialsRequestDTO`, `RefreshRequestDTO` |

---

## 2. Why it is structured this way

### 2.1 The dependency picture

```
                            ┌──────────────────────────────── Presentation ───────────────────────────────┐
                            │  LoginView ─▶ LoginViewModel                                                   │
                            └───────────────────────────────┬───────────────────────────────────────────────┘
                                                            │ depends on a PROTOCOL
                                                            ▼
                                                  AuthRepository  (Domain)
                                                            ▲ implemented by
                                                            │
                            ┌─────────────────────────── Data ──────────────────────────────┐
                            │  AuthRepositoryImpl ──▶ AuthRemoteDataSource ──▶ HTTPClient(protocol)
                            │          │                                              ▲
                            │          └──────────▶ TokenManager (actor) ──▶ SecureStore(protocol)
                            └─────────────────────────────────────────────────────────┼──────────┘
                                                                         URLSessionHTTPClient (plain, no token)
```

Arrows only point inward/downward. `LoginViewModel` has never heard of `URLSession`, JSON, Keychain or tokens.

### 2.2 Why a protocol AND an implementation? (`AuthRepository` / `AuthRepositoryImpl`)

- **The view model needs a capability ("log this person in"), not a mechanism.** The protocol is the capability. The impl is one way to provide it (HTTP + Keychain).
- **Swap-ability without touching callers.** Previews use `PreviewAuthRepository`, unit tests use `MockAuthRepository`; both slot in without any change to `LoginViewModel`. If one day login becomes "Sign in with Apple", only a new implementation is added.
- **Dependency inversion.** The high-level policy (`LoginViewModel`: "validate, log in, show errors") must not depend on low-level details (URLs, JSON). So the arrow points *to* the protocol, and the impl depends on it by conforming.
- Cost: one extra file. Benefit: the whole presentation layer compiles and can be previewed/tested with no network or Keychain.

### 2.3 Why a separate `AuthRemoteDataSource` instead of putting HTTP code inside the repository?

Single responsibility. They change for different reasons:

| `AuthRemoteDataSource` | `AuthRepositoryImpl` |
|---|---|
| Changes when the **API** changes (paths, DTOs, timeouts) | Changes when the **business flow** changes ("after login, store tokens") |
| Returns `AuthSession` | Returns `AuthUser` and has side effects (stores tokens) |
| Knows HTTP, not Keychain | Knows the token manager, not HTTP details |

It also is a `TokenRefresher` (`AuthRemoteDataSource.swift:5`) so the token manager can call `/refresh` through the same code that knows that endpoint, without importing the repository.

### 2.4 Why DTOs (`AuthResponseDTO`) *and* domain models (`AuthSession`)?

The server's JSON is a contract that belongs to the server. The app's models are what the app wants to work with. Example: the server sends `expiresIn: 900` (a duration), the app wants an absolute `accessTokenExpiresAt: Date`. The conversion lives in exactly one place (`AuthDTOs.swift:25`). If the backend renames a field, only the DTO changes.

### 2.5 Why two HTTP clients (plain vs authorized)?

`HTTPClient` is a protocol with two decorators-in-waiting:

| Client | Does | Used by |
|---|---|---|
| `URLSessionHTTPClient` | Sends the request. Knows nothing about tokens | `AuthRemoteDataSource` (login, register, refresh, logout) |
| `AuthorizedHTTPClient` | Wraps another `HTTPClient`; adds `Authorization: Bearer`; on 401 refreshes and retries once | `DeckRepositoryImpl` and every other protected API |

Why login **must not** go through the authorized client:
1. `/api/auth/*` must not carry a Bearer header (backend contract §8.1).
2. A **401 on login means "wrong password"**, not "token expired". If login went through the authorized client, a wrong password would trigger a pointless refresh-and-retry, and a refresh needs the *authorized* client... a loop. The split makes that impossible.
3. The token manager calls refresh through the plain client, which is how the dependency cycle `AuthorizedHTTPClient → TokenManager → refresh → AuthorizedHTTPClient` is avoided.

The `requiresAuth` flag on `Endpoint` (`Endpoint.swift:15`) is a second safety net: even if an auth call were wrongly sent through the authorized client, it would skip the token.

### 2.6 Why `Endpoint` is a value, not a method per call

`Endpoint` is plain data (path, method, body, flags). A client can inspect, log, retry or decorate it (`addingHeader`, `Endpoint.swift:45`). That is what lets `AuthorizedHTTPClient` retry the *same* request with a new header, which a hard-coded `func login()` could not.

### 2.7 Why `TokenManager` is an `actor` and its collaborators are not

Only the token manager has **shared mutable state touched by many concurrent callers** (the cached access token and the in-flight refresh). An actor makes that safe. Everything else (`AuthRepositoryImpl`, `AuthRemoteDataSource`, clients) holds only `let` constants, so they are plain `struct`s: no state, nothing to protect, trivially `Sendable`.

### 2.8 Why `SessionStore` is separate from `LoginViewModel`

The login screen is only *one* way the app becomes signed-in (restoring a session at launch is another; being thrown out when the refresh token dies is a third). "Who is logged in" must live in one app-wide place that `RootView` watches. So `LoginViewModel` doesn't set the state; it reports success through a closure (`onAuthenticated`) and `SessionStore` decides. It also keeps the view model free of any knowledge of the rest of the app.

### 2.9 Why a closure for `onAuthenticated` instead of a protocol or a `SessionStore` reference?

It is one function, one direction, one call. A closure is the lightest way to say "tell whoever created me". A protocol would be more ceremony; a `SessionStore` reference would make the login view model depend on app-level state.

### 2.10 Why the view model validates before calling the repository

Instant feedback with zero network cost, and fewer pointless server calls. The rules are mirrored from the backend (`CredentialsValidator`), but the server stays authoritative: it can still reject something the client accepted, and the view model handles that too (`present`, `LoginViewModel.swift:46`).

---

## 3. Before anyone logs in: how the objects get wired

This runs once at app launch, before the login screen exists.

| # | Function | Where | What happens |
|---|---|---|---|
| 1 | `flashcardsai_iOSApp.init()` | `flashcardsai_iOSApp.swift:9` | SwiftUI starts the app and runs this |
| 2 | `AppContainer.live()` | `AppContainer.swift:32` | Reads config, builds the container |
| 3 | `AppConfig.load()` | `Core/Config/AppConfig.swift` | Resolves `API_BASE_URL` (env var, Info.plist, or the DEBUG `localhost:8080` default). Throws → the app shows `ConfigurationErrorView` instead |
| 4 | `AppContainer.init(config:…)` | `AppContainer.swift:17` | Creates the object graph (below) |
| 5 | `container.makeSessionStore()` | `AppContainer.swift:36` | Creates `SessionStore`, giving it the repository and `tokenManager.events` |
| 6 | `WindowGroup` body | `flashcardsai_iOSApp.swift:21` | Shows `RootView(container:sessionStore:)` |
| 7 | `RootView.task { restore() }` | `RootView.swift:28` | Starts the launch check (section 9). With no stored session it ends with `state = .signedOut` |
| 8 | `RootView.body` switch | `RootView.swift:10` | `.signedOut` → `AuthFlowView(authRepository:onAuthenticated:)` (`RootView.swift:13-15`) |
| 9 | `AuthFlowView.init` | `AuthFlowView.swift:9` | Creates `LoginViewModel(authRepository:onAuthenticated:)` (`:12`) and keeps it in `@State` |

The object graph built in step 4 (`AppContainer.swift:22-29`):

```
plainClient   = URLSessionHTTPClient(baseURL, urlSession)             :22   (no tokens)
authRemote    = AuthRemoteDataSource(client: plainClient)             :23   (also a TokenRefresher)
tokenManager  = TokenManager(store: KeychainSecureStore(),
                             refresher: authRemote)                    :24
authorizedCl. = AuthorizedHTTPClient(base: plainClient, tokens: tokenManager)   :25
authRepository= AuthRepositoryImpl(remote: authRemote, tokenManager:) :28
deckRepository= DeckRepositoryImpl(client: authorizedClient)          :29
```

Key point: **`authRemote` and `tokenManager` both use `plainClient`; only the deck repository uses the authorized client.**

`onAuthenticated` is `sessionStore.didAuthenticate`, handed down by `RootView` (`:15`) → `AuthFlowView.init` (`:9`) → `LoginViewModel.init` (`:18`). Remember this; it is the last frame of a successful login.

---

## 4. The login trace

**Scenario:** the login screen is showing. The user types `alice@example.com` and `correct-horse-battery`, then taps **Log in**.
`@MainActor` = the main thread. "Hop" = the code continues on a different executor.

### Phase A: typing (no network, no repository)

| Step | What happens | Where |
|---|---|---|
| A1 | `AppTextField(text: $viewModel.email, …)`. `$viewModel.email` is a `Binding<String>` made possible by `@Bindable var viewModel` | `LoginView.swift:4`, `:18` |
| A2 | Each keystroke makes the text field call the binding's setter, which assigns `viewModel.email` | inside `AppTextField` (`Components.swift:72`) |
| A3 | `LoginViewModel` is `@Observable`, so SwiftUI is told the property changed and refreshes only the views that read it | `LoginViewModel.swift:4-8` |
| A4 | The email field's return key is labelled "next": `.onSubmit { focused = .password }` moves the cursor. The password field's key is labelled "go": `.onSubmit(submit)` **runs the same function as the button** | `LoginView.swift:22`, `:28` |
| A5 | `contentType: .username / .password` lets iOS autofill from iCloud Keychain / password managers | `LoginView.swift:19`, `:26` |

The password is just a `String` property in memory until the request is sent. It is never saved to disk, logged, or put in the Keychain.

### Phase B: the tap

**Frame 1 `LoginView.submit()`** (`LoginView.swift:58`) · main actor
- `Button(action: submit)` (`:34`) calls it.
- `focused = nil` (`:59`) dismisses the keyboard.
- `Task { await viewModel.submit() }` (`:60`) starts an asynchronous unit of work. It is created here because a button action cannot be `async`. The new `Task` inherits the main actor, so `LoginViewModel.submit` runs on the main thread until it first has to wait.

**Frame 2 `LoginViewModel.submit()`** (`LoginViewModel.swift:23`) · main actor
Line by line:
- `:24` `guard !isLoading else { return }`: double-tap protection (the button is also `.disabled` while loading, `LoginView.swift:38`).
- `:25` `errorMessage = nil`: clears the old banner.
- `:27` `emailError = CredentialsValidator.emailError(email)`:
  - **Frame 2a `CredentialsValidator.emailError(_:)`** (`CredentialsValidator.swift:14`) trims whitespace via **2b `normalizedEmail`** (`:10`), then checks: empty → "Enter your email."; longer than 254 → "Email is too long."; must split at `@` into exactly 2 non-empty parts, a domain containing `.` that doesn't start/end with `.`, and no spaces → else "Enter a valid email address."; otherwise returns `nil` (valid).
- `:28` `passwordError = password.isEmpty ? "Enter your password." : nil`. Login deliberately does *not* apply the 8-character minimum; only registration does.
- `:29` `guard emailError == nil, passwordError == nil else { return }`: **if either is set, we stop here.** The fields show their inline errors and no network call happens.
- `:31` `isLoading = true` → the button's `LoadingLabel` shows a spinner and the button disables.
- `:32` `defer { isLoading = false }` is armed. It runs on every exit path from here (success, error, cancellation).
- `:35-37` `try await authRepository.login(email: CredentialsValidator.normalizedEmail(email), password: password)`:
  - `authRepository` is declared as the **protocol** `AuthRepository` (`:15`). At runtime it is `AuthRepositoryImpl` (from the container).
  - The email is normalised again (trimmed) so what is sent is exactly what was validated.
  - `await` = the main thread is released here; the UI stays responsive. `submit` resumes when the call returns or throws.

**Frame 3 `AuthRepositoryImpl.login(email:password:)`** (`AuthRepositoryImpl.swift:18`) · not on the main actor
(`AuthRepositoryImpl` is a plain struct, so under Swift's rules for nonisolated `async` functions this runs on the background executor, not the main thread.)
- `:19` `let session = try await remote.login(email:password:)` → Frame 4.
- `:20` `try await tokenManager.adopt(session.tokens)` → Frame 11 (after the server answered).
- `:21` `return session.user`.
The ordering matters: **the tokens are stored before the user is reported as logged in.** If storing fails, login fails visibly instead of leaving a "logged in" UI with nothing to refresh later.

**Frame 4 `AuthRemoteDataSource.login(email:password:)`** (`AuthRemoteDataSource.swift:22`)
- `:23-25` builds the request description with **Frame 5** `Endpoint.json(path: "/api/auth/login", body: CredentialsRequestDTO(email:password:), requiresAuth: false)`.
- `:26` `let response: AuthResponseDTO = try await client.send(endpoint)` → **Frame 6**. Declaring the result type is what tells the generic `send` what to decode into.
- `:27` `return response.toSession(receivedAt: now())` → **Frame 10**.
`client` is the `HTTPClient` protocol; here it is `plainClient` (a `URLSessionHTTPClient`), as wired in section 3.

**Frame 5 `Endpoint.json(path:method:body:requiresAuth:timeout:)`** (`Endpoint.swift:33`)
- `:40` `try JSONCoding.makeEncoder().encode(body)` (**5a** `JSONCoding.makeEncoder`, `JSONCoding.swift:18`) turns `CredentialsRequestDTO` into bytes:
  `{"email":"alice@example.com","password":"correct-horse-battery"}`
- `:38` creates the `Endpoint` via its `init` (`:19`): `path: "/api/auth/login"`, `method: .post` (the default, `:34`), `requiresAuth: false`, `timeout: nil`, `headers: [:]`.
- `throws` only if encoding fails (practically never for two strings).

**Frame 6 `HTTPClient.send<Response>(_:as:)`** (the generic extension, `HTTPClient.swift:10`)
- `:11` `let data = try await send(endpoint)`: calls the *protocol requirement* (the bytes version), implemented by **Frame 7**.
- `:13` decodes `data` into `Response` (= `AuthResponseDTO`) with **6a** `JSONCoding.makeDecoder()` (`JSONCoding.swift:4`). Any decode failure becomes `APIError.decoding(...)` (`:15`).

**Frame 7 `URLSessionHTTPClient.send(_:)`** (`URLSessionHTTPClient.swift:13`)
- `:14` `let request = try makeRequest(for: endpoint)` → **7a**:
  - **`makeRequest`** (`:37`): strips the leading `/` from the path (`:38`), `baseURL.appending(path:)` (`:39`) → `http://localhost:8080/api/auth/login`; sets `httpMethod = "POST"` (`:42`), header `Accept: application/json` (`:43`); because there is a body: `httpBody` and `Content-Type: application/json` (`:44-47`); applies `timeoutInterval` only if the endpoint set one (`:48-50`); copies any extra headers (`:51-53`). **There is no `Authorization` header** because the endpoint carries none and this client never adds one.
- `:19` `(data, response) = try await session.data(for: request)` **← the app now waits for the network.** The thread is free, the spinner is on screen.

*(The request travels to the backend; see section 6. A response comes back.)*

- `:25` `guard let http = response as? HTTPURLResponse` else `APIError.invalidResponse`.
- `:27-34` `switch http.statusCode`:
  - `200..<300` → `return data` (success, back to Frame 6).
  - `401` → `throw APIError.unauthorized(decodeProblem(from: data))`.
  - anything else → `throw APIError.http(status:problem:)`.
  - **7b `decodeProblem`** (`:57`): tries to read the backend's `ProblemDetail` JSON (`title`, `status`, `detail`, `errors`); returns `nil` if the body is empty or isn't that shape.
- If `session.data` itself throws (offline, timeout, …): `:20-23` → `CancellationError` for `.cancelled`, otherwise `APIError.transport(code)`.

**Frame 8 (back in Frame 6)**: the status was 200, so `data` is JSON like

```json
{"accessToken":"eyJ…","refreshToken":"q3j8…","tokenType":"Bearer","expiresIn":900,
 "user":{"id":1,"email":"alice@example.com"}}
```
`JSONDecoder` fills `AuthResponseDTO` (`AuthDTOs.swift:18`) and `UserDTO` (`:12`). Returned to Frame 4.

**Frame 10 `AuthResponseDTO.toSession(receivedAt:)`** (`AuthDTOs.swift:25`)
Builds the domain values:
- `AuthTokens(accessToken, refreshToken, accessTokenExpiresAt: now + 900s)`, so the app can tell later whether the access token is still valid without asking the server.
- `AuthUser(id: 1, email: "alice@example.com")`.
- Returns `AuthSession(tokens:user:)`, back to Frame 3 (`:19`).

**Frame 11 `TokenManager.adopt(_:)`** (`TokenManager.swift:78`) · hop onto the **actor's** executor (this is the `await` at `AuthRepositoryImpl.swift:20`)
- `:80` `try store.save(tokens.refreshToken, for: "refreshToken")` → **11a `KeychainSecureStore.save`** (`SecureStore.swift:42`):
  - `SecItemUpdate` first (`:44`): is there already an item? If not found (`:46`) → `SecItemAdd` (`:52`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`:51`): readable after first unlock, never synced/backed up.
  - A failure logs the `OSStatus` (`:55`, `:59`) and throws `KeychainError`.
- `:81-83` any storage error becomes `APIError.storage(...)`.
- `:84-85` keeps the **access token and its expiry in memory only**.
- Returns. The actor is free again.

**Frame 12** back in `AuthRepositoryImpl.login` (`:21`): `return session.user` → an `AuthUser` goes back up to the view model. (The session's tokens now live only inside `TokenManager`; the view model never sees them.)

**Frame 13 `LoginViewModel.submit` resumes** (`LoginViewModel.swift:35`) · back on the main actor
- `:38` `onAuthenticated(user)`: calls the closure it was created with. That closure is `sessionStore.didAuthenticate` (wired at `RootView.swift:15`).
- **13a `SessionStore.didAuthenticate(_:)`** (`SessionStore.swift:53`): `state = .signedIn(user)`.
- `:32` the `defer` runs: `isLoading = false` (the spinner would stop, but the screen is about to go away).

**Frame 14 SwiftUI reacts** (`RootView.swift:10`)
`RootView` reads `sessionStore.state` (it is `@Observable`), so the change re-evaluates its body: the `switch` now takes `.signedIn(let user)` (`:16`) → `MainTabView(...).id(user.id)` (`:17-22`), cross-faded by `.animation(.easeInOut, value:)` (`:27`).
- `AuthFlowView` is removed from the tree, so its `LoginViewModel` (holding the email and password strings) is deallocated.
- `.id(user.id)` gives the tab UI a fresh identity per user, so a different account never inherits another account's screen state.

Login complete: Keychain has the refresh token, `TokenManager` has the access token, `SessionStore` says signed-in, the UI shows the tabs.

### Concurrency map for the trace

| Frames | Runs on |
|---|---|
| 1, 2, 13, 13a, 14 | main actor (UI) |
| 3, 4, 5, 6, 7, 10 | background (nonisolated async work) |
| 7 `session.data(for:)` | system networking, no thread blocked |
| 11, 11a | `TokenManager` actor (serialised) |

---

## 5. The same trace as a call stack

What the "stack" looks like at the moment the app is waiting for the server (innermost = most recent). Every `await` is a suspension point; the frames above it are parked until it completes.

```
 ┌ URLSession.data(for:)                         URLSessionHTTPClient.swift:19   ← waiting for the network here
 │ URLSessionHTTPClient.send(_:)                 URLSessionHTTPClient.swift:13
 │ HTTPClient.send<AuthResponseDTO>(_:as:)       HTTPClient.swift:11
 │ AuthRemoteDataSource.login(email:password:)   AuthRemoteDataSource.swift:26
 │ AuthRepositoryImpl.login(email:password:)     AuthRepositoryImpl.swift:19
 │ LoginViewModel.submit()                       LoginViewModel.swift:35
 │ Task { await viewModel.submit() }             LoginView.swift:60
 └ LoginView.submit()  ◀ Button(action: submit)  LoginView.swift:58 / :34
```

Chronological list of **every function that runs on a successful login** (including the pure helpers):

```
 1  LoginView.submit                          LoginView.swift:58
 2  LoginViewModel.submit                     LoginViewModel.swift:23
 3    CredentialsValidator.emailError         CredentialsValidator.swift:14
 4      CredentialsValidator.normalizedEmail  CredentialsValidator.swift:10
 5    CredentialsValidator.normalizedEmail    (again, for the value actually sent)
 6  AuthRepositoryImpl.login                  AuthRepositoryImpl.swift:18
 7    AuthRemoteDataSource.login              AuthRemoteDataSource.swift:22
 8      Endpoint.json                         Endpoint.swift:33
 9        JSONCoding.makeEncoder              JSONCoding.swift:18
10        Endpoint.init                       Endpoint.swift:19
11      HTTPClient.send<Response>             HTTPClient.swift:10
12        URLSessionHTTPClient.send           URLSessionHTTPClient.swift:13
13          URLSessionHTTPClient.makeRequest  URLSessionHTTPClient.swift:37
14          URLSession.data(for:)             ← network round trip
15        JSONCoding.makeDecoder              JSONCoding.swift:4
16        JSONDecoder.decode(AuthResponseDTO)
17      AuthResponseDTO.toSession             AuthDTOs.swift:25
18    TokenManager.adopt                      TokenManager.swift:78
19      KeychainSecureStore.save              SecureStore.swift:42
20  LoginViewModel: onAuthenticated(user)     LoginViewModel.swift:38
21    SessionStore.didAuthenticate            SessionStore.swift:53
22  RootView.body re-evaluates                RootView.swift:10   → MainTabView
```

---

## 6. What the backend does during that one call

(Details in the backend `DOCUMENTATION.md` §4.) Between frames 14 and 7's response:

```
POST /api/auth/login
  Spring Security filter chain: /api/auth/** is public; any Authorization header is ignored there
  AuthController.login(@Valid LoginRequest)
  AuthService.login
    normalizeEmail                      trim + lowercase
    userRepository.findByEmail
    fitsBcryptLimit                     password ≤ 72 bytes
    passwordEncoder.matches             BCrypt compare (against a dummy hash if the email is unknown, to equalise timing)
    ─ mismatch / unknown user: throw InvalidCredentialsException ─▶ GlobalExceptionHandler ─▶ 401 ProblemDetail "Invalid email or password."
    issueTokens
      tokenService.generateRefreshToken, hashRefreshToken, refreshTokenRepository.save
      tokenService.createAccessToken    signed JWT, 15 min
  ─▶ 200 AuthResponse JSON
```

---

## 7. Failure traces (the "error frames")

An error is `throw`n at the innermost frame and **unwinds upward** through each `try await` until a `catch` handles it. Nothing in the middle swallows or rewrites it, so there is exactly one place that decides what the user sees (`LoginViewModel`).

### 7.1 Wrong password (the most common failure)

```
THROWN  URLSessionHTTPClient.send           URLSessionHTTPClient.swift:31   throw APIError.unauthorized(ProblemDetail)   ← server said 401
  ↑     HTTPClient.send<Response>           HTTPClient.swift:11             try await send(endpoint)   (propagates; no decode happens)
  ↑     AuthRemoteDataSource.login          AuthRemoteDataSource.swift:26   (propagates)
  ↑     AuthRepositoryImpl.login            AuthRepositoryImpl.swift:19     (propagates; adopt() is never reached, so NOTHING is stored)
  ↑     LoginViewModel.submit               LoginViewModel.swift:35         CAUGHT at :41  ─▶ present(error) (:46)
```
`present` (`LoginViewModel.swift:46`):
1. `error as? APIError` succeeds. `apiError.fieldErrors` (`APIError.swift:24`) is `[:]` (a 401 has no per-field map), so `emailError`/`passwordError` stay `nil`.
2. `errorMessage = error.userMessage` (`:52`):
   - `Error.userMessage` (`APIError.swift:61`) → `LocalizedError.errorDescription` (`:37`) → `.unauthorized(problem)` case (`:45`) → `problem?.detail` = **"Invalid email or password."**
3. `LoginView` shows it in an `ErrorBanner` (`LoginView.swift:30-32`). `defer` resets `isLoading`.

Why the app does **not** try to refresh here: the request went through the plain client, which has no refresh logic (section 2.5).

### 7.2 Validation fails locally (no network at all)

```
LoginView.submit ─▶ LoginViewModel.submit :27-29  ─▶ guard fails ─▶ return
```
Inline messages appear under the fields ("Enter a valid email address." / "Enter your password."). Nothing was thrown; no repository call happened.

### 7.3 No internet / server down

```
THROWN  URLSessionHTTPClient.send   :19-22   URLError(.notConnectedToInternet / .cannotConnectToHost …)  ─▶ APIError.transport(code)
  ↑     … same upward path as 7.1 …
  ↑     LoginViewModel.submit       :41 catch ─▶ present ─▶ errorMessage
```
`APIError.errorDescription` (`APIError.swift:41`): `isConnectivityIssue` (`:26`) is true → **"Can't reach the server. Check your connection and try again."**
If the backend isn't running you get `.cannotConnectToHost`, which is in that same list (`:28-29`).

### 7.4 Request timed out

Same as 7.3 with `URLError.timedOut` (also in the connectivity list). Default timeout is 60 s; there is no custom timeout on login.

### 7.5 Server error (500, 502…)

`URLSessionHTTPClient.swift:33` → `APIError.http(status:problem:)`. Message: the backend's `detail` if there is one, else "The server had a problem. Please try again later." (`APIError.swift:47-50`).

### 7.6 Server answered 200 with a body the app can't decode

`HTTPClient.swift:14-15` → `APIError.decoding(...)` → "Something went wrong talking to the server. Please try again." The technical detail stays in the error value (visible in the debugger), never on screen.

### 7.7 Login succeeded on the server but the Keychain refused to save

```
THROWN  KeychainSecureStore.save    SecureStore.swift:56 (or :60)   KeychainError(status)   [also logged, category "keychain"]
  ↑     TokenManager.adopt          TokenManager.swift:81-83        wrapped as APIError.storage(...)
  ↑     AuthRepositoryImpl.login    AuthRepositoryImpl.swift:20
  ↑     LoginViewModel.submit       :41 ─▶ message "Couldn't access your saved session securely on this device."
```
Important consequence: the **server already created a session** (a refresh-token row), but the app never got to use it. It is simply orphaned and expires in ≤ 30 days. The user can tap Log in again. The commonest cause in development is an **unsigned build** (`OSStatus -34018`); see `DOCUMENTATION.md` §4.

### 7.8 Task cancelled

`URLError.cancelled` is converted to `CancellationError` (`URLSessionHTTPClient.swift:21`). `LoginViewModel` catches it first (`:39-40`) and returns silently (no error banner), because cancellation is not a failure the user should read about.

### 7.9 Server returns a field-level 400

(Rare for login because the client validates first.) `problem.errors = {"email": "…"}` → `apiError.fieldErrors["email"]` (`LoginViewModel.swift:48`) → shown under the email field, and `present` returns early (`:50`) so no banner appears as well.

### 7.10 Error → message cheat sheet

| Thrown | Created at | Final text on screen |
|---|---|---|
| `.unauthorized(problem)` | `URLSessionHTTPClient.swift:31` | the server's `detail` ("Invalid email or password.") |
| `.http(status, problem)` | `:33` | server `detail`, else a generic server-error text |
| `.transport(code)` | `:22` | "Can't reach the server…" (connectivity codes) / "A network error occurred…" |
| `.decoding` | `HTTPClient.swift:15` | "Something went wrong talking to the server…" |
| `.invalidResponse` | `URLSessionHTTPClient.swift:25` | same generic text |
| `.storage` | `TokenManager.swift:82` | "Couldn't access your saved session securely…" |
| `CancellationError` | `URLSessionHTTPClient.swift:21` | nothing |
| `.sessionExpired` | `TokenManager` refresh paths (not on login) | "Your session has expired. Please log in again." |

---

## 8. Register: what differs

`RegisterViewModel.submit` → `AuthRepository.register` → `AuthRepositoryImpl.register` (`:12`) → `AuthRemoteDataSource.register` (`:14`, path `/api/auth/register`) → same `Endpoint.json` / `send` / `toSession` / `tokenManager.adopt` frames as login → `onAuthenticated(user)` → `.signedIn`. The backend answers **201** (any 2xx is success).

Differences are all in the view model (`Features/Auth/Presentation/RegisterViewModel.swift`):
- Validates three fields: `CredentialsValidator.emailError`, `passwordError` (≥ 8 characters, ≤ 72 **bytes**, the BCrypt limit) and `confirmationError` (passwords match).
- A **409** (`APIError.http(409, _)`) is mapped to the email field: "An account with this email already exists."
- Server field errors (`errors.email`, `errors.password`) go under the matching field.
- Text-content type is `.newPassword` so iOS can suggest a strong password.

---

## 9. App launch / session restore trace

Runs at every launch (from `RootView.task`, `RootView.swift:28`).

```
RootView.task                                   RootView.swift:28
 └ SessionStore.restore()                       SessionStore.swift:36     state = .launching (LaunchView)
    └ authRepository.restoreSession()           AuthRepositoryImpl.swift:24
       └ TokenManager.restoreSession()          TokenManager.swift:90
          ├ readRefreshToken()                  TokenManager.swift:179 → KeychainSecureStore.read (SecureStore.swift:23)
          │    nothing stored  ─▶ return nil ─────────────▶ restore(): state = .signedOut      (login screen)
          │    Keychain READ ERROR ─▶ throw .storage ─────▶ restore(): state = .launchFailed   (Try again; NOT logged out)
          └ performRefresh()                    TokenManager.swift:132   (joins or creates the single in-flight refresh)
             └ runRefresh()                     TokenManager.swift:141
                ├ readRefreshToken()
                ├ refresher.refreshSession(refreshToken:)  = AuthRemoteDataSource.swift:30 ─▶ POST /api/auth/refresh (plain client, no Bearer)
                │     401  ─▶ expireSession() (:188: clear() + yield .expired) ─▶ throw .sessionExpired ─▶ restore(): .signedOut
                │     offline / 5xx ─▶ rethrow (tokens kept) ──────────────────▶ restore(): .launchFailed (Try again)
                ├ generation check (user logged out meanwhile? drop the result)
                ├ KeychainSecureStore.save(NEW refresh token)   ← before anything else uses it
                └ keep the new access token + expiry in memory; return the session
       └ `.user` of that session                AuthRepositoryImpl.swift:25 ─▶ restore(): state = .signedIn(user)
```
Why a refresh at launch? The access token is never saved to disk, so after a cold start the app has none. Exchanging the refresh token yields a fresh one and also tells us who the user is.

---

## 10. Logout trace

```
ProfileView "Log out" ─▶ confirmation ─▶ onLogout()          RootView.swift:21  { await sessionStore.logout() }
 └ SessionStore.logout()                                      SessionStore.swift:57
    └ authRepository.logout()                                 AuthRepositoryImpl.swift:28
       ├ tokenManager.currentRefreshToken                     TokenManager.swift:73   (read the token we need to revoke)
       ├ tokenManager.clear()                                 TokenManager.swift:115
       │     bump sessionGeneration, cancel a running refresh, wipe memory, delete the Keychain item
       └ remote.logout(refreshToken:)  (try?, errors ignored) AuthRemoteDataSource.swift:38   POST /api/auth/logout, 5 s timeout
    └ state = .signedOut                                      SessionStore.swift:59
 └ RootView swaps to AuthFlowView → a brand-new LoginViewModel with empty fields
```
Local logout happens **first** so the user is signed out on the device even if the server is slow or unreachable.

---

## 11. After login: how the access token is used

Protected calls (decks) use the *authorized* client:

```
DeckListViewModel.fetch ─▶ DeckRepositoryImpl.fetchDecks ─▶ AuthorizedHTTPClient.send ─▶ URLSessionHTTPClient.send
                                                              │
                              tokens.validAccessToken() ◀─────┤  TokenManager.swift:96  (cached? > 30 s left? else refresh)
                              adds  Authorization: Bearer <token>
                              401?  ─▶ tokens.refreshAccessToken(afterRejecting:) (TokenManager.swift:104) ─▶ retry ONCE
```
Details, concurrency rules and the single-flight refresh: `docs/TokenManager.md`.

---

## 12. Session-expiry trace (the `AsyncStream` path)

```
... runRefresh: server answers 401 to /refresh                         TokenManager.swift:154-159
 └ expireSession()                                                      TokenManager.swift:188
    ├ clear()                                                           (tokens gone)
    └ eventContinuation.yield(.expired)           ──▶ pipe ──▶  SessionStore's `for await event in events`   SessionStore.swift:25
                                                                  └ handle(.expired)  SessionStore.swift:62 ─▶ state = .signedOut
                                                                       └ RootView shows AuthFlowView (login)
 └ throws APIError.sessionExpired to the request that triggered the refresh (so its caller also unwinds)
```
The stream is only for this "the session is dead, tell the UI" signal. Why a stream and not a callback or notification: `docs/TokenManager.md` §4.

---

## 13. Design Q&A

**Q: Why not have `LoginViewModel` call `URLSession` directly? It'd be fewer files.**
Then the view model could only be tested/previewed with a network, would know JSON and URLs, and every future screen (register, deck list…) would repeat the same plumbing. The layers cost a few files and buy swap-ability, tests and one place to fix each kind of change.

**Q: Why `struct` for repository/remote/clients but `class`/`actor` for stores?**
Structs with only `let` properties are immutable and automatically thread-safe. State that changes and is shared needs a reference type: `SessionStore` (UI state, main actor, `@Observable` requires a class) and `TokenManager` (shared mutable tokens, so an actor).

**Q: Why does `AuthRepositoryImpl.login` return `AuthUser` and not the whole session?**
The tokens are an internal concern of the token manager. Returning them would invite view models to hold or log them. The UI only needs to know *who* signed in.

**Q: Why store the refresh token before reporting success?**
So "signed in" never exists without the ability to stay signed in. A storage failure surfaces at login, not hours later when the access token expires.

**Q: Why does the 401 from login not trigger a refresh like other 401s?**
Because login uses the plain client. A 401 there is a credential answer, not an expiry. Only `AuthorizedHTTPClient` (protected calls) interprets 401 as "refresh".

**Q: Why `isLoading` and `defer`?**
`isLoading` drives the spinner and disables the button. `defer` guarantees it is reset on every exit path (success, any error, cancellation) so the button can't get stuck.

**Q: Why `Task { }` in the view instead of making `submit` `async` for the button?**
`Button` actions are synchronous. `Task` is the bridge into async code. The view model's `submit` stays `async`, which makes it directly awaitable in tests.

**Q: Why is the error text built in `APIError`, not in the view model?**
One source of truth for wording across the whole app (login, decks, create-deck). The view model only decides *where* to show it (field vs banner).

**Q: Why `.id(user.id)` on `MainTabView`?**
So when account B signs in after account A, SwiftUI discards all of A's view state (selected tab, navigation stack, loaded decks) instead of reusing it.

---

## 14. Honest weak spots

- **`AuthUser` lives in `Core/Security/AuthModels.swift`, not `Features/Auth/Domain`.** It sits in Core because `TokenManager` (Core) needs it. A cleaner split would give Core its own small `SessionIdentity` or move `TokenManager` into the Auth feature. Not worth a refactor yet, but it is a layering shortcut.
- **`AuthRepositoryImpl` depends on the concrete `AuthRemoteDataSource` and `TokenManager`, not protocols.** That is simpler, but it means the repository itself can't be unit-tested without real instances (they are cheap to build with stubs, which is how the existing tests do it). Protocols could be extracted if that becomes painful.
- **Login has no rate-limit or lockout feedback** (the backend has none yet). Repeated wrong passwords just show the same message.
- **The login `Task` is unstructured**, so leaving the screen mid-request does not cancel it. The result still arrives and `onAuthenticated` can fire after the user navigated away (harmless today because it only sets `signedIn`).
- **Passwords are plain `String`s in memory** for the duration of the form. That is normal for iOS apps; they are never written anywhere.
- **No automated tests yet for the `TokenManager` hardening** (generation guard, Keychain read errors; see `docs/TokenManager.md` §7).

---

## 15. Quick index

| I want to understand… | Open |
|---|---|
| What happens when I tap Log in | §4 and §5 |
| Why a wrong password shows that message | §7.1 |
| How the app knows I'm still logged in after relaunch | §9 |
| What logout does | §10 |
| How tokens refresh without me noticing | `docs/TokenManager.md` |
| Why so many types | §2 |
| Where a type is created | §3 (`AppContainer.swift:17-30`) |
| What a given error means on screen | §7.10 |
