# Flashcards AI – iOS Documentation

Living document. Update it in the same change as the code; add a line to the **Change log** (section 14).

Backend repo: `../flashcards-ai` (its `DOCUMENTATION.md` §8 is the API contract this app implements).

---

## 1. Overview & status

SwiftUI app that lets a user register / log in with email + password, generate flashcard decks for any topic (Gemini does the generation on the backend), browse their decks and study them with interactive flip cards.

| Area | Status |
|---|---|
| Register, login, logout, session restore on launch | Built |
| Token handling (access in memory, rotating refresh token in Keychain, refresh-and-retry on 401) | Built |
| Decks tab: list, create (topic + difficulty), deck detail | Built |
| Study mode: flip cards for MCQ, True/False and Q&A, summary, missed-card review | Built |
| Score tab (local, per user) | Built |
| Profile tab (account info, logout) | Built |
| Delete deck | Repository method exists (`DeckRepository.deleteDeck`), **no UI yet** (backend delete not yet manually tested) |
| Local notifications, Live Activities, deep links | Planned, see §12 for where they plug in |
| UI tests | Not written yet (decision: features first). Unit tests exist, see §10 |

**Verified so far:** the project compiles for the simulator without warnings, and the unit tests (§10) passed when last run. **Not yet verified by a human:** running the app against the real backend. Use the checklist in §11.

---

## 2. Technology decisions

- **SwiftUI**, deployment target **iOS 18.5**, Swift language mode 5. The code follows Swift 6 concurrency habits (`Sendable` types, actors, `@MainActor` view models) but has only been compiled in Swift 5 mode, so strict-concurrency warnings are not yet verified.
- **State:** the Observation framework (`@Observable`, `@Bindable`, `@State`). No `ObservableObject`/Combine.
- **Concurrency:** `async/await`, `actor`, `Task`, `AsyncStream`, task groups only in tests. No completion handlers.
- **Networking:** `URLSession` only. **No third-party packages.**
- **Architecture:** MVVM + clean architecture (§3), SOLID, composition root DI (§5.5).
- **Secrets:** none in the app (the Gemini key lives on the backend). Only the API base URL is configurable (§4).

---

## 3. Architecture

### 3.1 Layers and the dependency rule

```
Presentation (Views, ViewModels)  ──depends on──▶  Domain (models, repository protocols, pure logic)
                                                        ▲
Data (DTOs, remote/local data sources, repo impls) ─────┘ implements
```

- **Domain** knows nothing about SwiftUI, URLSession or Keychain. It contains entities (`Deck`, `Card`, `ScoreRecord`…), repository **protocols** and pure logic (`StudySession`, `CredentialsValidator`).
- **Data** converts wire formats (DTOs) to domain models and implements the repository protocols.
- **Presentation** view models talk only to protocols, which is why they can be previewed with fakes (`Core/Preview/PreviewData.swift`) and unit tested with mocks.
- Use cases were deliberately **not** added as pass-through classes: a repository call wrapped in a use case adds ceremony without behaviour. Logic that deserves a home (the study state machine, credential validation) lives in Domain types. Introduce a use case the day a flow needs to orchestrate several repositories.

### 3.2 SOLID in practice

| Principle | Where |
|---|---|
| Single responsibility | `URLSessionHTTPClient` = transport only; `AuthorizedHTTPClient` = bearer + retry only; `TokenManager` = token lifecycle only; `JSONCoding` = date/JSON rules only |
| Open/closed | New feature = new folder; new endpoint = new `Endpoint` + repository method. `HTTPClient` is decorated (`AuthorizedHTTPClient`) instead of modified |
| Liskov | Every `HTTPClient`/`ScoreRepository`/`SecureStore` implementation is interchangeable (real, preview fake, test double) |
| Interface segregation | `TokenProviding` (what the HTTP decorator needs) and `TokenRefresher` (what the manager needs) are tiny protocols instead of one fat auth service |
| Dependency inversion | View models and repositories receive protocols; only `AppContainer` names concrete types |

### 3.3 Folder structure

```
flashcardsai-iOS/
  App/
    flashcardsai_iOSApp.swift     @main, builds the container, shows RootView or ConfigurationErrorView
    RootView.swift                switches on SessionStore.state (launch / login / tabs / retry)
    MainTabView.swift             Decks · Score · Profile tabs (selection comes from DeepLinkRouter)
    SessionStore.swift            app-wide auth state (@Observable)
    DeepLinkRouter.swift          pending deep link + selected tab + Decks path (@Observable)
  Core/
    Config/AppConfig.swift        API base URL resolution
    Networking/                   Endpoint, HTTPClient, URLSessionHTTPClient, AuthorizedHTTPClient,
                                  APIError, ProblemDetail, JSONCoding (+ ISO8601DateParser)
    Security/                     SecureStore (+ Keychain impl), TokenManager, AuthModels
    DesignSystem/                 Components, FlipCardView (Theme lives in Shared/)
    Widgets/WidgetSnapshotPublisher.swift   writes the newest decks for the widget
    LiveActivities/LiveStudyActivityController.swift   ActivityKit: start / update / end the study Live Activity
    Notifications/                UserNotificationReminderScheduler (local reminders), NotificationTapHandler (taps -> router)
    DI/AppContainer.swift         composition root
    Preview/PreviewData.swift     DEBUG-only sample data + fake repositories for #Preview
  Features/
    Auth/      Domain · Data · Presentation
    Decks/     Domain · Data · Presentation
    Study/     Domain · Presentation        (pure state machine + flip-card UI)
    Score/     Domain · Data · Presentation
    Profile/   Presentation
    Reminders/ Domain · Presentation        ("Remind me" for a deck: view model, sheet, section)
Shared/                           compiled into the app AND the widget: AppGroup, DeepLink, Theme, WidgetSnapshot, StudyActivityAttributes
FlashcardsWidget/                 widget extension (timeline provider, small/large views, study Live Activity UI)
Info.plist                        only CFBundleURLTypes (flashcardsai://), merged into the generated plist
flashcardsai-iOSTests/            unit tests + Support/TestDoubles.swift
flashcardsai-iOSUITests/          Xcode template only
```

The Xcode project uses **synced folders**: any `.swift` file added under `flashcardsai-iOS/` is part of the app target, under `Shared/` part of both app and widget, and under `FlashcardsWidget/` part of the widget.

### 3.4 Going modular later

Each `Features/<Name>` folder only depends on `Core` and its own layers, so any feature can be promoted to a local Swift Package (`Packages/DecksFeature`, …) by moving its folder and exposing a small public entry view. Do this when build times or team size justify it, not before.

---

## 4. Configuration (no secrets, nothing hard-coded)

`Core/Config/AppConfig.swift` resolves the API base URL in this order:

0. **DEBUG builds only:** the address saved from the login/register screen (`DebugServerOverride`)
1. Environment variable **`API_BASE_URL`**
2. Info.plist key **`API_BASE_URL`**
3. **DEBUG builds only:** `http://localhost:8080`

Release builds have no default, and **must be `https`**. If nothing valid is found the app shows a "Configuration error" screen instead of crashing.

### Setting it during development

**Easiest (DEBUG builds): in the app.** The login and register screens show the server in use. Tap it, type the address (e.g. `http://<your-mac-ip>:8080` for a real iPhone and your Mac), tap **Save**, then fully quit and reopen the app. It is stored on the device (`UserDefaults`, key `debug.apiBaseURL`, see `DebugServerOverride`), so it works however the app is launched. **Use default** clears it. Invalid values are rejected on save and ignored on read, so a typo can't stop the app from starting. Release builds never read it.

**Alternative: scheme environment variable.** It only exists when Xcode launches the app (not from the home-screen icon), which is why the in-app setting above is easier.

Xcode → Product → Scheme → Edit Scheme… → Run → Arguments → **Environment Variables** → add `API_BASE_URL` = `http://<your-mac-ip>:8080` (for a real device, use your Mac's LAN IP). Scheme user data is git-ignored (`xcuserdata/`).

### Setting it for release builds (when you get there)

Create `Config/Release.xcconfig` (git-ignored; commit a `Release.example.xcconfig` without real values) containing `API_BASE_URL = https:/$()/api.yourdomain.com`, attach it to the Release configuration, and add the Info.plist entry `API_BASE_URL = $(API_BASE_URL)`.

### Things to watch

- **Plain HTTP:** iOS App Transport Security blocks cleartext HTTP to normal hosts. The simulator reaching `http://localhost:8080` is the expected dev setup but **has not been verified yet**. If a request fails with `-1022` ("App Transport Security policy"), add `NSAppTransportSecurity → NSAllowsLocalNetworking = YES` to the Debug Info.plist only. A real device calling your Mac's LAN IP may also trigger the Local Network permission prompt.
- **Keychain needs a signed build.** An app built with `CODE_SIGNING_ALLOWED=NO` has no entitlements and Keychain access fails (`OSStatus -34018`), surfacing as "Couldn't access your saved session securely on this device." Running from Xcode signs automatically, so this only matters for command-line builds. The OSStatus is logged under subsystem = bundle id, category `keychain`.

---

## 5. Core layer

### 5.1 Networking

> Full explanation (component reference, lifecycles, the reasoning behind each decision, how iOS networking layers are generally built, interview cheat sheet, how to add an endpoint, and the TODO/betterments table): **[`docs/Networking.md`](docs/Networking.md)**.

```
Repository ──▶ AuthorizedHTTPClient ──▶ URLSessionHTTPClient ──▶ backend
                (adds Bearer, refresh+retry)   (transport, error mapping)
AuthRemoteDataSource ──────────────────────▶ URLSessionHTTPClient   (no Bearer: /api/auth/*)
```

- `Endpoint`: path, method, JSON body, `requiresAuth`, optional timeout, headers. `Endpoint.json(...)` encodes a body.
- `HTTPClient.send(_:) -> Data` returns the 2xx body (empty for 204); an extension decodes `Decodable` results.
- `URLSessionHTTPClient`: builds the request, maps results:

| Result | Becomes |
|---|---|
| 2xx | `Data` |
| 401 | `APIError.unauthorized(ProblemDetail?)` |
| other status | `APIError.http(status:problem:)` |
| `URLError` | `APIError.transport(code)` (`.cancelled` becomes `CancellationError`) |
| undecodable body | `APIError.decoding` |

- `ProblemDetail` mirrors the backend's RFC 9457 body (`title, status, detail, instance, errors`). `APIError.fieldErrors` exposes the `errors` map of a 400 so forms can show per-field messages.
- `Error.userMessage` returns text safe to show to users (server `detail` when present, friendly fallbacks otherwise, a "can't reach the server" message for connectivity errors).
- **Dates:** `JSONCoding` decodes the backend's UTC instants (`2026-10-20T15:35:11.123456Z`). The fraction may have 0, 3, 6 or 9 digits, and `ISO8601DateFormatter` is unreliable past milliseconds, so `ISO8601DateParser` normalises the fraction to milliseconds first.
- Create-deck uses a **90 s** timeout (Gemini is slow); everything else uses the URLSession default.
- The `URLSession` ignores the local cache (`reloadIgnoringLocalCacheData`) so authenticated data is never served from disk.

### 5.2 Token management (`Core/Security/TokenManager.swift`)

> Full walkthrough with sequence diagrams, the reasoning behind each design choice (actor, single flight, `AsyncStream`) and known limitations: **[`docs/TokenManager.md`](docs/TokenManager.md)**.

An `actor` that is the single owner of the token lifecycle.

| | Access token | Refresh token |
|---|---|---|
| Storage | memory only | Keychain only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: usable by future background work, never synced/backed up) |
| Lifetime | 15 min (server) | up to 30 days, **rotated on every refresh** |

Rules enforced:

1. **Proactive refresh:** `validAccessToken()` refreshes when the token has less than 30 s left, so most requests never see a 401.
2. **Reactive refresh:** a protected request that gets 401 triggers `refreshAccessToken(afterRejecting:)` and is retried **once** (`AuthorizedHTTPClient`). No retry loops.
3. **Single flight:** concurrent callers share one in-flight refresh `Task`. This matters because the backend treats a *reused* refresh token as theft and revokes the whole session; two parallel refreshes would log the user out.
4. **Already refreshed by someone else?** If the rejected token is no longer the current one, the new current token is returned without another network call.
5. **Persist before use:** the new refresh token is written to the Keychain *before* the new access token is handed out (the old refresh token is dead the moment the server answers).
6. **Only a definitive 401 on refresh ends the session:** tokens are cleared and `SessionEvent.expired` is emitted (observed by `SessionStore`, which shows the login screen). Offline, timeouts and 5xx keep the tokens, so being on a train never logs you out.
7. `restoreSession()` is used at launch: with a stored refresh token it refreshes and returns the user; with none it returns `nil`.

### 5.3 Keychain (`SecureStore`)

Protocol with `read/save/delete`; `KeychainSecureStore` is the production implementation (generic password items scoped by service = bundle id). Tests use an in-memory implementation.

### 5.4 Design system

White + light-blue theme, with dark-mode variants (`Theme.swift`, colours resolve dynamically per trait).

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | #1670BE | #5BB8FF | buttons, links, selection (≥ 4.5:1 with `onPrimary`) |
| `lightBlue` | #4DB3FF | #4DB3FF | decoration: gradients, rings, glows |
| `backgroundTop` → `background` | #DDF0FF → white | #0E2236 → #08131F | screen gradient |
| `surface` / `surfaceTint` | white / #EAF6FF | #13283B / #1A3550 | cards / chips |
| `textPrimary` / `textSecondary` | #0F2A40 / #56718A | #F2F8FD / #A3B8CC | text |
| `success` / `danger` | #1E8E5A / #C0392B | #4CD08B / #FF7A6B | correct / wrong |

Also `Theme.Spacing`, `Theme.Radius`, `Theme.Typography` (rounded system fonts, scale with Dynamic Type except the fixed display sizes).

Components (`Components.swift`): `AppBackground`, `.cardSurface()`, `PrimaryButtonStyle`, `SecondaryButtonStyle`, `LoadingLabel`, `AppTextField` (icon, secure toggle, inline error), `ErrorBanner`, `EmptyStateView`, `Badge`, `StatTile`.

### 5.5 Composition root (`Core/DI/AppContainer.swift`)

The only place that creates concrete types:

```
URLSessionHTTPClient(plain) ──▶ AuthRemoteDataSource ──(TokenRefresher)──▶ TokenManager(KeychainSecureStore)
        └──────────────▶ AuthorizedHTTPClient(plain, TokenManager) ──▶ DeckRepositoryImpl
AuthRepositoryImpl(AuthRemoteDataSource, TokenManager)
makeScoreRepository(userID:) ──▶ UserDefaultsScoreRepository
makeSessionStore()           ──▶ SessionStore(authRepository, tokenManager.events)
```

`AuthRemoteDataSource` uses the *plain* client on purpose: refreshing must not go through the component that triggers refreshing (no cycle, no Bearer on auth endpoints).

---

## 6. App shell & navigation

- `SessionStore` (`@Observable`, `@MainActor`) holds `state`: `.launching`, `.signedOut`, `.signedIn(AuthUser)`, `.launchFailed(message)`.
  - `restore()` at launch: stored session → `signedIn`; none → `signedOut`; refresh rejected → `signedOut`; **server unreachable → `launchFailed` with a retry button** (the user is *not* logged out for being offline).
  - Listens to `TokenManager.events`; `.expired` (refresh token rejected at any point) moves to `signedOut`.
- `RootView` switches on the state with a fade. `MainTabView(...).id(user.id)` guarantees all view models and navigation state are rebuilt when a **different account** signs in, so account A's data never appears for account B.
- `MainTabView`: `TabView` with **Decks**, **Score**, **Profile**; each owns its own `NavigationStack`. The selected `AppTab` is `DeepLinkRouter.selectedTab`.
- Decks navigation uses a typed path `[DecksRoute]` (`.detail(DeckSummary)`, `.study(Deck)`) stored in `DeepLinkRouter.decksPath`, so taps and deep links drive the same state.
- Deep links (`flashcardsai://...`), the router and the widget are described in `docs/DeepLinksAndWidget.md`.

---

## 7. Auth feature (`Features/Auth`)

> Function-by-function walkthrough of login (every call from the tap to the tabs), the error traces, the launch/logout flows and the reasoning behind the protocol / impl / remote / DTO structure: **[`docs/AuthLayer.md`](docs/AuthLayer.md)**.

**Domain:** `AuthRepository` (protocol: `register`, `login`, `restoreSession`, `logout`), `CredentialsValidator` (mirrors backend rules for instant feedback).

**Data:** `AuthDTOs` (`CredentialsRequestDTO`, `RefreshRequestDTO`, `AuthResponseDTO` → `AuthSession`; token expiry = receive time + `expiresIn`), `AuthRemoteDataSource` (register/login/refresh/logout against `/api/auth/*`, `requiresAuth = false`), `AuthRepositoryImpl` (hands tokens to `TokenManager.adopt`, returns the user). Logout calls the server best-effort, then always clears local credentials.

**Presentation:** `AuthFlowView` (NavigationStack) → `LoginView` → push `RegisterView`; `LoginViewModel`, `RegisterViewModel`.

Validation (client side, server remains authoritative):
- Email: trimmed, shape `x@y.z`, ≤ 254. (The backend rejects emails with surrounding spaces, so the app trims.)
- Password (register): ≥ 8 characters and ≤ 72 **bytes** (BCrypt limit).
- Confirmation must match.
- Server errors: 400 `errors` map → shown under the matching field; 409 → "An account with this email already exists."; 401 on login → the server's "Invalid email or password."; offline → connectivity message.
- Text-content types are set (`.username`, `.password`, `.newPassword`) so iCloud Keychain / password manager autofill works.

---

## 8. Decks feature (`Features/Decks`)

- **Domain:** `Deck`, `DeckSummary`, `Card`, `Difficulty` (BEGINNER / INTERMEDIATE / ADVANCED), `CardType` (QA / MCQ / TRUE_FALSE) (raw values are the exact backend strings), `DeckRepository` (`fetchDecks`, `fetchDeck`, `createDeck`, `deleteDeck`).
- **Data:** `DeckDTOs` (`DeckDTO`, `CardDTO`, `DeckSummaryDTO`, `CreateDeckRequestDTO`) with `toDomain()` mappers (`options: null` becomes `[]`), `DeckRepositoryImpl` on the authorized client.
- **Presentation:**
  - `DeckListView` / `DeckListViewModel`: newest first, pull-to-refresh, empty state with a call to action, error banner that keeps the existing list on refresh failure.
  - `CreateDeckView` / `CreateDeckViewModel`: topic (trimmed, 1–100 chars), suggestion chips, difficulty segmented picker, blocking "Generating your deck…" overlay (sheet cannot be dismissed while generating), server errors (e.g. Gemini 502) shown inline. On success the sheet closes and the new deck's detail opens.
  - `DeckDetailView` / `DeckDetailViewModel`: loads the full deck, shows counts per card type, lists questions, **Start studying**.
- Every deck request is scoped to the signed-in user by the backend (token subject). Another user's deck id returns 404.

---

## 9. Study, Score, Profile

### 9.1 Study (`Features/Study`)

`StudySession` (Domain, pure value type, no UI/I/O) is the state machine; `StudyViewModel` wraps it; `StudyView` renders it.

| Card type | User action | Grading |
|---|---|---|
| MCQ | tap one of 4 options | automatic (`correctIndex`, falling back to comparing `answer`) |
| TRUE_FALSE | tap True / False | automatic (`answer == "True"`) |
| QA | tap the card or **Reveal answer**, then **Got it / Missed it** | self-graded |

Flow per card: `answering` → (answer/reveal) → `revealed(selection, isCorrect?)` → **Next card** / **See results**. Answers cannot be changed after the flip; QA cannot be skipped without grading; actions for the wrong card type are ignored.

**Animation:** `FlipCardView` is `Animatable`; SwiftUI feeds it every angle of a spring-animated 0° → 180° Y-rotation (perspective 0.5) and it swaps front/back at 90° (edge-on). The back face is pre-rotated 180° so text isn't mirrored. Cards slide between each other (`asymmetric` move + opacity). Result ring on the summary animates its trim. **Reduce Motion:** the flip becomes a cross-fade and the slide becomes a fade.

**Gestures (Q&A cards only):** MCQ and True/False must be answered by choosing an option, so a swipe would let people skip the question.
- *Drag the question side sideways:* the card turns with the finger (`FlipCardView(dragAngle:)`, angle = drag × 0.5, capped at ±170°). Past ~45° or with a quick flick (predicted end > 220 pt) it completes the flip in the direction of the drag and reveals the answer; otherwise it springs back. Tapping the card or **Reveal answer** still works.
- *After the answer is shown:* swipe right = **Got it**, swipe left = **Missed it**. The card follows the finger with a slight tilt and a green/red stamp that fades in; past 110 pt (or a fast flick) it flies off, is graded, and the next card slides in. Short swipes spring back.
- Mostly-vertical drags are ignored so the text's `ScrollView` still scrolls. A cancelled gesture (alert, system gesture) settles the card via `@GestureState`.
- Implementation: `StudyCardStage` in `StudyView.swift` owns the gesture state, and `StudyView` gives each card its own stage with `.id(card.id)`, so state resets per card. A light haptic fires when a Q&A card is revealed.
- The Got it / Missed it buttons and **Reveal answer** stay as the accessible and discoverable alternatives (gestures are invisible to VoiceOver/Switch Control users and are hinted at in the card footers). With **Reduce Motion** the drag doesn't rotate the card; a short drag/flick just triggers the cross-fade reveal.
- Not yet verified on a device; it only compiles. Things to check by hand: drag feel on both directions, flick sensitivity, text scrolling in long answers, and the fly-off timing.

Other touches: hint toggle (💡 per card), progress bar + `n/total`, MCQ back face lists all options with the right one green and a wrong choice red, haptics (`sensoryFeedback` success/error), summary with accuracy ring, headline, **Review these** (missed questions with answers), **Study again** (reshuffled) and **Done**.

Accessibility: icon-only buttons have labels, option buttons read "Option A: …", result rows read correct/incorrect, the score ring has a spoken summary.

A finished run saves exactly one `ScoreRecord` (restart re-arms it).

### 9.2 Score (`Features/Score`)

The backend has **no score API**, so scores are stored on-device: `ScoreRepository` (protocol) → `UserDefaultsScoreRepository(userID:)`, key `scores.v1.user.<id>` (per account, newest first, capped at 200). `ScoreStats` aggregates sessions, cards answered, average and best accuracy. `ScoreView` shows four stat tiles + recent sessions and an empty state. To move scores to the server later, add a remote `ScoreRepository` implementation and swap it in `AppContainer`; no view model changes.

### 9.3 Profile (`Features/Profile`)

Avatar with the email's initial, email, app version/build, server host (DEBUG builds only), **Log out** with confirmation (server logout best-effort, local credentials always cleared).

---

## 10. Tests

Unit tests exist (written before the "features first, tests later" decision) in `flashcardsai-iOSTests`; no UI tests yet. Run:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project flashcardsai-iOS.xcodeproj -scheme flashcardsai-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:flashcardsai-iOSTests
```

Last full run: **114 test cases passed, 0 failed** (Swift Testing). The preview-data and Keychain-logging additions made afterwards were only build-checked.

Coverage: date parsing (0/3/6/9 fraction digits), `AppConfig` resolution rules, credential validation, decoding of the backend's documented JSON shapes (contract tests), `URLSessionHTTPClient` request building and error mapping (via a `URLProtocol` stub), `AuthorizedHTTPClient` (bearer attach, one retry, no loops), `TokenManager` (expiry, leeway, rotation persistence, single flight with 8 concurrent callers, definitive vs transient failure, restore, clear), `StudySession` for every card type, login/register/session/deck/study view models, score storage and stats. Test doubles live in `Support/TestDoubles.swift`.

---

## 11. Manual verification checklist

Backend running (`localhost:8080`) and Docker Postgres up. Run the app from Xcode on a simulator (**signed build**, so Keychain works). For the visual parts alone, open the `#Preview`s in Xcode (no backend needed): Study session, Login/register, Decks tab, Create deck, Score, Profile, Main tabs.

1. **Register** a new account → lands on the Decks tab (empty state).
2. Kill and relaunch the app → still signed in (session restore, brief launch screen).
3. **Create a deck** (e.g. "Swift concurrency", Beginner) → overlay while generating, then the deck detail with card counts.
4. **Study:** answer an MCQ (card flips, right/wrong colouring, explanation), a True/False, and a Q&A (tap card or Reveal, then Got it / Missed it). Check Next card / See results, the summary ring, Review these, Study again.
5. **Score tab** shows the session; **Profile** shows the email; **Log out** returns to login.
6. **Log in as a second account** → decks list is empty and the Score tab has none of the first account's history. Log back into the first account → its decks return.
7. **Token refresh:** wait > 15 min (or temporarily set `app.jwt.access-token-ttl=30s` on the backend), then pull-to-refresh the deck list → it works without a login prompt.
8. **Offline:** turn the Mac's Wi-Fi off, relaunch while signed in → "Can't connect" with Try again (not logged out); reconnect and retry.
9. **Wrong password** shows "Invalid email or password."; a duplicate email on register shows the inline conflict message.
10. Settings → Accessibility → Reduce Motion on: the card cross-fades instead of flipping. Dark mode: screens use the navy palette.

If login fails with "Couldn't access your saved session securely on this device", check the console for the `keychain` log line (see §4).

---

## 12. Extending the app

**Add a feature:** create `Features/<Name>/{Domain,Data,Presentation}`, define a repository protocol in Domain, implement it in Data using `HTTPClient`, build the view model against the protocol, register the implementation in `AppContainer`, add a tab or route.

**Local notifications (built for per-deck reminders, see `docs/Notifications.md`):** `ReminderScheduling` protocol, `UserNotificationReminderScheduler`, `NotificationTapHandler` (tap -> `DeepLink` -> `router.receive`), `Features/Reminders`. Next candidates: daily reminder + settings screen, streak nudges, remote push.

**Live Activities (built for study sessions, see `docs/LiveActivities.md`):** originally planned as: the Widget Extension target already exists (`FlashcardsWidget`, App Group `group.com.flashcardsai.flashcardsai-iOS`); add an `ActivityAttributes` type for a study session; start/update/end the activity from `StudyViewModel` through a small `StudyActivityControlling` protocol injected like any other dependency (keeps the view model testable).

**Deep links (built):** see `docs/DeepLinksAndWidget.md`. To make a new inner screen deep-linkable add a route, a router path, a `DeepLink` case + parser rule, and handle it in `DeepLinkRouter.applyPending`. Notification taps should call `router.receive(DeepLink(...))`.

**Swap score storage / add delete deck / sync:** implement the protocol, change one line in `AppContainer`.

---

## 13. Known limitations / TODO

- Delete-deck has no UI (backend delete flow still to be verified manually).
- No rate-limit or retry/backoff UI for Gemini failures beyond showing the server message.
- Scores are device-local and don't sync between devices.
- Release configuration (xcconfig for `API_BASE_URL`, https backend, app icon, signing) is not set up yet.
- Email verification / password reset / account deletion are not in the backend yet (the latter is an App Store requirement before release).
- The simulator → `http://localhost:8080` path and a real-device run are unverified (see §4).
- Deep links, the widget, the study Live Activity and deck reminders compile but are unverified on a device (checklist in `docs/DeepLinksAndWidget.md` §9). A pending deep link never expires and stays pending if the first deck list load fails.
- `.gitignore` doesn't untrack files already committed: `flashcardsai-iOS.xcodeproj/xcuserdata/` is in the initial commit. Run `git rm -r --cached flashcardsai-iOS.xcodeproj/xcuserdata` once before pushing.

---

## 14. Change log

### Deck reminders (local notifications)
- "Remind me today" on the deck detail screen: sheet with quick choices or a time picker (today only), permission asked on first use, one reminder per deck (`reminder.deck.<id>`), shown as "Reminder set" with Change / Cancel. The notification carries `flashcardsai://deck/<id>`; `NotificationTapHandler` (assigned early in the app `init`, kept alive by the app) validates it with `DeepLink(url:)` and hands it to `DeepLinkRouter`. `SessionStore.signOut()` cancels all pending and delivered reminders. Docs: `docs/Notifications.md`.

### Study session Live Activity
- `NSSupportsLiveActivities` in the root `Info.plist`; `Shared/StudyActivityAttributes` (deck id/name/total + answered/correct/finished); UI in the widget extension (Lock Screen banner, Dynamic Island expanded/compact/minimal); `StudyActivityControlling` protocol + `LiveStudyActivityController` (ActivityKit, serial queue, fails soft). `StudyViewModel` starts it on appear, updates on `next()`, ends on finish or when the screen goes away; `SessionStore` ends all activities on launch and sign-out. Docs: `docs/LiveActivities.md`.

### Deep links and home-screen widget
- `Shared/` folder (compiled into app and widget): `DeepLink` (parser + `url`), `AppGroup`, `Theme` (moved from `Core/DesignSystem`), `WidgetSnapshot` + App Group store.
- URL scheme `flashcardsai://` registered through a root `Info.plist` merged into the generated one. `.onOpenURL` at the app root → `DeepLinkRouter` (pending link, selected tab, Decks path). Deck links only open decks already in the loaded list; otherwise an alert. Pending link survives signed-out launch and is applied after login; cleared when a signed-in session ends.
- `MainTabView` / `DecksTabView` now read tab selection and path from the router.
- Widget extension `FlashcardsWidget` (small + large, light/dark; medium was dropped because it clipped the rows) reading a snapshot the app writes via `DeckSnapshotPublishing` / `WidgetSnapshotPublisher`; `SessionStore` clears it on every sign-out. App Group capability on both targets.
- Docs: `docs/DeepLinksAndWidget.md`.

### Debug server address setting
- New `DebugServerOverride` (UserDefaults, DEBUG only, validated) and `DebugServerLabel` (tap the server line on the login/register screens to change it). `AppConfig.load` gained a `debugOverride` parameter (highest priority in DEBUG) and a reusable `AppConfig.parse`. Reason: scheme environment variables vanish when the app isn't launched by Xcode, so a real iPhone silently fell back to `localhost`.

### Study gestures
- Q&A cards: drag-to-flip (interactive, either direction, flick support) and swipe right/left to grade after the reveal; `FlipCardView` gained `dragAngle`/`flipDirection` and switches faces on `abs(angle) >= 90`. Card hints updated ("Tap or swipe…", "Swipe right if you knew it…").
- Also in this round: Debug-only server URL label on the login and register screens.

### Docs: Networking layer
- Added `docs/Networking.md` and linked it from §5.1. Includes a prioritised list of gaps (no query parameters, no retry/backoff, no PUT/PATCH, `Data`-only responses, idle-only timeouts, no logging, stringly-typed paths…).

### Docs: Auth layer walkthrough
- Added `docs/AuthLayer.md` (login call trace with file:line frames, error traces, register/launch/logout/expiry flows, design rationale, weak spots) and linked it from §7.

### TokenManager hardening
- A Keychain **read error** no longer logs the user out (`readRefreshToken()` throws `.storage`; launch offers *Try again*). Error text is now "Couldn't access your saved session securely on this device." The launch-failed screen is titled "Couldn't open your account" (it covers more than connectivity).
- `clear()` bumps a `sessionGeneration`, cancels the in-flight refresh, and a refresh that returns after logout writes nothing back (and cannot emit a stale `.expired`).
- Logout order changed: local session cleared first, then the best-effort server call with a 5 s timeout.
- A failed Keychain delete on logout is now logged (category `tokens`).
- Not covered by automated tests yet; the 114 existing tests still pass.

### Docs: TokenManager deep dive
- Added `docs/TokenManager.md` (flows, design rationale, outcome matrix, known limitations) and linked it from §5.2.

### Initial build: foundation, auth, decks, study, score, profile
- Replaced the Xcode template (`ContentView`, template app/test files).
- Added `Core` (config, networking, Keychain, `TokenManager`, design system, DI container, preview data), `App` shell (session store, root view, tabs) and the `Auth`, `Decks`, `Study`, `Score`, `Profile` features as described above.
- Added unit tests and test doubles (§10).
- Added `.gitignore` (Xcode artefacts, `.xcconfig`, `.env`, signing files), `CLAUDE.md`, this document.
- Keychain failures now log their `OSStatus`; `#Preview`s with fake repositories added for the main screens.
- Removed an end-to-end UI test that was written during the build: it registered real users and called Gemini on the dev backend, and the decision is to verify manually first.
