# TokenManager: how it works and why

Source: `flashcardsai-iOS/Core/Security/TokenManager.swift` (+ `AuthorizedHTTPClient.swift`, `SessionStore.swift`).
Backend contract it implements: backend `DOCUMENTATION.md` §4.1 and §8.

---

## 1. The problem it solves

The backend gives a login two tokens:

| | Access token | Refresh token |
|---|---|---|
| Purpose | proves who you are on every `/api/decks/**` call | only used to get a new pair |
| Life | **15 minutes** | up to 30 days |
| Backend rule | stateless JWT | **single use**: each refresh returns a NEW refresh token and kills the old one |
| If replayed | n/a | the backend assumes theft and **revokes the whole session** |

So the app has to: keep the user logged in for weeks, renew the 15-minute token invisibly, always remember the newest refresh token, never use a refresh token twice (even when many requests fail at once), and tell the UI if the session truly died. `TokenManager` is the one object that does all of this, so no screen or view model ever handles a token.

---

## 2. The pieces

```
                   ┌──────────────────────────── TokenManager (actor) ────────────────────────────┐
 Repositories ───▶ │  accessToken + expiry   (memory only)                                        │
   via             │  refreshTask            (the single in-flight refresh, if any)               │
 AuthorizedHTTP    │  events: AsyncStream    ──────────────▶ SessionStore (shows login screen)    │
 Client            │                                                                              │
 (TokenProviding)  │  store: SecureStore  ─▶ Keychain  (refresh token only)                       │
                   │  refresher: TokenRefresher ─▶ AuthRemoteDataSource ─▶ POST /api/auth/refresh │
                   └──────────────────────────────────────────────────────────────────────────────┘
```

| Type | Role |
|---|---|
| `TokenProviding` | The small interface `AuthorizedHTTPClient` needs: `validAccessToken()` and `refreshAccessToken(afterRejecting:)` |
| `TokenRefresher` | The small interface the manager needs to call the backend (`refreshSession(refreshToken:)`). Implemented by `AuthRemoteDataSource`, which uses the plain HTTP client, so there is no loop (refreshing never goes through the thing that triggers refreshing) |
| `SecureStore` | Keychain wrapper (in-memory in tests) |
| `SessionEvent` | What the manager announces to the app. Currently only `.expired` |
| `AuthTokens` / `AuthSession` | Access + refresh + access expiry / tokens + user |

State held by the manager: `accessToken`, `accessTokenExpiry`, `refreshTask`. The refresh token is never held in a property; it is read from the Keychain when needed, so the Keychain is the single source of truth.

---

## 3. Flows

### 3.1 Login / register: `adopt`

```
LoginViewModel ─▶ AuthRepositoryImpl.login
                     ├─ AuthRemoteDataSource.login ─▶ backend ─▶ AuthSession
                     └─ tokenManager.adopt(tokens)
                           ├─ Keychain.save(refreshToken)      (throws APIError.storage on failure)
                           └─ accessToken / expiry = in memory
```

### 3.2 A normal request

```
DeckRepository ─▶ AuthorizedHTTPClient.send(/api/decks)
   └─ tokens.validAccessToken()
        access token present and expires in > 30 s?  ──yes──▶ return it (no network)
   └─ send request with  Authorization: Bearer <token>
```

### 3.3 Proactive refresh (token about to expire)

```
validAccessToken(): token has ≤ 30 s left (the "leeway")  or  there is no access token in memory
   └─ performRefresh()  ─▶  (see 3.5)  ─▶ returns the NEW access token
```
Why 30 s: a token that is valid when we check could expire while the request is on the wire. Refreshing slightly early avoids most 401s.

### 3.4 Reactive refresh (the server said 401)

```
AuthorizedHTTPClient                           TokenManager                       Backend
  send(request, "Bearer A") ───────────────────────────────────────────────────▶  401
  ◀── APIError.unauthorized
  refreshAccessToken(afterRejecting: "A") ───▶
                                               accessToken != "A" and still fresh?
                                                 yes: someone already refreshed → return it
                                                 no : performRefresh() ───────────▶ POST /refresh
                                               ◀──────────────────────────────── new pair
  retry ONCE with "Bearer B" ───────────────────────────────────────────────────▶  200
```
Only one retry: if the retry is also 401 the error is thrown (no infinite loop). The reactive path exists because proactive refresh can't cover everything (server/phone clock skew, token revoked server-side).

### 3.5 Concurrent requests: "single flight"

The deck list, a detail screen and a score refresh all fire at the moment the token has expired:

```
Request 1 ─▶ validAccessToken ─▶ performRefresh: no task yet ─▶ creates refreshTask ─▶ POST /refresh (refresh token R0)
Request 2 ─▶ validAccessToken ─▶ performRefresh: refreshTask exists ─▶ awaits the SAME task ┐
Request 3 ─▶ validAccessToken ─▶ performRefresh: refreshTask exists ─▶ awaits the SAME task ┤
                                                                                              ▼
                                  backend answers (access A1, refresh R1) ─▶ saved ─▶ all three get A1
```
Without this, requests 2 and 3 would each send `R0` too. R0 is already dead after the first call, so the backend would see a reused refresh token, call it theft, and revoke the session: the user is logged out for no reason. **One refresh, shared by everyone**, is the most important property of this class.

Implementation: `performRefresh()` returns the stored `refreshTask` if there is one, otherwise creates `Task { try await self.runRefresh() }` and stores it. `runRefresh()` clears `refreshTask` in a `defer` when it finishes (success or failure). All the work (reading the Keychain, calling the backend, saving, error translation) happens *inside* the task, so every waiter gets the same result or the same error.

### 3.6 What `runRefresh` does, step by step

```
0. remember `generation = sessionGeneration`
1. read refresh token from Keychain
      item not found            ─▶ expire the session, throw .sessionExpired
      Keychain read ERROR       ─▶ throw .storage; tokens and session kept (an error is not "logged out")
2. POST /api/auth/refresh with it
      401 (server rejected it)  ─▶ if the generation is unchanged: expireSession() (clear tokens + emit .expired);
                                   throw .sessionExpired
      offline / timeout / 5xx   ─▶ rethrow the error; tokens untouched (user stays logged in)
2b. back from the network: generation changed? (clear() ran, i.e. the user logged out meanwhile)
      yes ─▶ throw CancellationError and write NOTHING back
3. success: SAVE THE NEW REFRESH TOKEN TO THE KEYCHAIN FIRST (the old one is dead server-side now)
      Keychain write fails      ─▶ throw .storage
4. store the new access token + expiry in memory
5. return the session
```
Why step 3 comes before 4: if the app were killed between receiving the response and saving, the next launch would hold a dead refresh token and the user would be logged out. Saving first makes that window as small as it can be.

### 3.7 App launch: `restoreSession`

```
SessionStore.restore()  ─▶ AuthRepository.restoreSession ─▶ tokenManager.restoreSession()
   no refresh token in Keychain  ─▶ nil          ─▶ state = .signedOut  (login screen)
   refresh token present         ─▶ performRefresh ─▶ session.user      ─▶ state = .signedIn(user)
        refresh rejected         ─▶ .sessionExpired                     ─▶ .signedOut
        server unreachable       ─▶ transport error                     ─▶ .launchFailed (Try again; NOT logged out)
        Keychain read error      ─▶ .storage error                      ─▶ .launchFailed (Try again; NOT logged out)
```
At launch the access token isn't in memory (it is never persisted), so a refresh is how the app gets one, and it also returns the user for the profile.

### 3.8 Logout

`AuthRepositoryImpl.logout()`:

1. captures the current refresh token,
2. `tokenManager.clear()` **first**: bumps `sessionGeneration`, cancels any refresh still running, clears memory, deletes the Keychain item (a failed delete is logged, category `tokens`),
3. then calls `POST /api/auth/logout` with the captured token, best effort, **5 s timeout**, failures ignored.

`SessionStore` then sets `.signedOut`. Ending the local session before the network call means the user is logged out on the device even if the server is slow or unreachable, and a refresh that was racing with logout can no longer write a token back.

---

## 4. Why each design choice

### Why an `actor`?
Several tasks call the manager at the same time (that is the whole point of section 3.5). Its mutable state (`accessToken`, `refreshTask`…) would be a data race in a normal class. An actor serialises access, so "check for an existing refresh task, else create one" can never interleave between two callers. It gives thread-safety without locks, and the compiler enforces it.
Note that actors are *reentrant*: while one caller `await`s the network, another can enter. That is exactly why `refreshTask` is stored and why `runRefresh` re-reads state itself instead of trusting values captured before an `await`.

### Why is the refresh token in the Keychain and the access token only in memory?
The refresh token is the long-lived credential, so it gets the OS-protected store (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: usable after the first unlock so future background work can refresh, never synced to iCloud or other devices). The access token lives 15 minutes and can always be re-created from the refresh token, so persisting it adds risk for no gain.

### Why `AsyncStream<SessionEvent>`? (the question "why do we need it")
**The problem:** the session can die in a place far from any UI. A background refresh triggered three layers down inside `AuthorizedHTTPClient` gets a 401 from `/refresh`. The user must now be taken to the login screen, from code that knows nothing about views, view models or `SessionStore`. Options:

| Option | Why not |
|---|---|
| Throw an error and hope each caller handles it | There are many callers (every repository, every screen). One forgotten `catch` and the user sits on a broken screen. The rule "session over" should be handled once |
| Give `TokenManager` a reference to `SessionStore` / a callback | `Core` would depend on app-level UI state (wrong dependency direction), plus a retain cycle and an actor-to-`@MainActor` hop to manage by hand |
| `NotificationCenter` | Stringly-typed, global, untyped payloads, not checked by the compiler |
| Combine subject | Works, but this codebase deliberately uses only Swift concurrency |

**Why `AsyncStream` fits:**
- It is a *push* channel with a typed payload (`SessionEvent`), which the compiler checks.
- It is `Sendable`, so the actor can yield from its isolation and a `@MainActor` consumer can read from another: `SessionStore` just does `for await event in events` in a task.
- It **buffers**: if `.expired` is emitted before the consumer is iterating (for example during launch restore, before the listener task has started), it is still delivered when the consumer starts. A plain closure callback would silently lose it.
- It keeps the dependency pointing the right way: `TokenManager` knows nothing about `SessionStore`; `SessionStore` subscribes.
- Every other path still throws a normal error. The stream is the *additional* "tell the whole app" broadcast for the one event that must never be missed.

How it is built: `AsyncStream.makeStream(of:)` returns both the stream and its `continuation` in `init`. The continuation is kept privately and only `expireSession()` calls `eventContinuation.yield(.expired)`. The stream is exposed as `nonisolated let events` so `AppContainer` can hand it to `SessionStore` synchronously (no `await`), which is allowed because it is an immutable `Sendable` constant.
Limitation: an `AsyncStream` supports **one** consumer. That is correct today (only `SessionStore` listens). If a second listener is ever needed (for example analytics), add a small fan-out (a list of continuations, or a broadcaster) instead of iterating the same stream twice.

### Why `now` and `leeway` are injected
`now: @Sendable () -> Date` lets tests move the clock instead of sleeping for 15 minutes; `leeway` (30 s) is the early-refresh window.

### Why only a 401 from `/refresh` ends the session
401 is the backend's definitive "this refresh token is invalid, expired or revoked". Everything else (no internet, timeout, 502, 500) says nothing about the token. Treating those as "log out" would drop users every time they enter a tunnel, so tokens stay and the error propagates (the UI shows a connectivity message or the retry screen).

### Why `sessionGeneration`
A refresh can be in the air while the user taps *Log out*. Without protection it would return afterwards and write fresh tokens into the Keychain: a logged-out user who is silently signed back in on the next launch. `clear()` increments a counter and cancels the task; a refresh compares the counter before it writes anything (and before it announces `.expired`) and drops its result if it changed. The same counter stops a stale "session expired" from signing out someone who has already logged back in, and stops an old refresh's cleanup from erasing the slot of a newer refresh.

### Why a Keychain read error is not "logged out"
`nil` ("no item") and a thrown error ("the read failed") mean different things. Treating the second as the first would sign the user out because of a transient device problem. `readRefreshToken()` keeps them apart: only "not found" ends the session; an error surfaces as `.storage` and the app offers *Try again*.

### Why protocols (`TokenProviding`, `TokenRefresher`, `SecureStore`)
Interface segregation and testability: the HTTP decorator can be tested with a stub provider, the manager with a stub refresher and an in-memory store, with no network or Keychain.

---

## 5. Method reference

| Member | Who calls it | What it does |
|---|---|---|
| `adopt(_:)` | `AuthRepositoryImpl` after login/register | saves the refresh token to the Keychain; keeps access token + expiry in memory |
| `validAccessToken()` | `AuthorizedHTTPClient` before each protected call | returns the cached token if it has > 30 s left, else refreshes (single flight) |
| `refreshAccessToken(afterRejecting:)` | `AuthorizedHTTPClient` after a 401 | returns the current token if it already differs from the rejected one and is fresh; otherwise refreshes |
| `restoreSession()` | `AuthRepositoryImpl` at launch | `nil` with no stored token; otherwise refreshes and returns the session (user included) |
| `clear()` | logout, `expireSession` | bumps `sessionGeneration`, cancels the in-flight refresh, wipes memory, deletes the Keychain item |
| `currentRefreshToken` | logout (to call the server) | reads the Keychain |
| `hasStoredSession` | `restoreSession` | is there a refresh token? |
| `events` | `SessionStore` | stream of `.expired` |
| `performRefresh()` *(private)* | the three methods above | joins or creates the single in-flight refresh task |
| `readRefreshToken()` *(private)* | `restoreSession`, `runRefresh` | Keychain read that distinguishes "not found" (`nil`) from "read failed" (throws `.storage`) |
| `runRefresh()` *(private)* | the refresh task | steps in 3.6 |
| `expireSession()` *(private)* | `runRefresh` | `clear()` + emit `.expired` |

## 6. Outcome matrix

| Situation | Result for the user |
|---|---|
| Access token valid | request just goes out |
| Access token expired / near expiry | silent refresh, request goes out |
| Server says 401 on a request | silent refresh + one retry |
| 10 requests need a refresh at once | one refresh call, all 10 succeed |
| Refresh token expired / revoked / reused | `.expired` event → login screen |
| No internet during refresh | request fails with a connectivity message; stay signed in |
| Backend down at launch | "Can't connect" screen with Try again; stay signed in |
| Keychain write fails after a refresh | error shown; the next refresh may fail (the new token was not stored) |
| Keychain read fails | `.storage` error ("Couldn't access your saved session…"); session kept; *Try again* at launch |
| User logs out while a refresh is running | the refresh is cancelled / its result dropped; nothing is written back |
| User logs out with no internet | logged out locally at once; the server call fails quietly (token expires server-side in ≤ 30 days) |

---

## 7. Known limitations and risks

Fixed since the first version: *Keychain read errors were treated as "no session"* (now thrown and kept, §4) and *a refresh finishing after logout could write tokens back* (now guarded by `sessionGeneration`, §4).

Still open:

1. **One consumer for `events`** (see §4). Fine today, needs a fan-out if a second listener appears.
2. **Single process only.** `refreshTask` lives in this app's memory. When a Widget / Live Activity / notification extension later needs to refresh using the same Keychain, two processes could refresh with the same token at once and trip the backend's theft detection. Plan for that before adding extensions: let only the main app refresh and give extensions the access token through a shared store, or add a cross-process lock.
3. After a successful refresh, if the Keychain write fails the old refresh token is already dead server-side. The user will be asked to log in again on the next refresh. This is unavoidable without server support, and is why the write happens first.
4. **Logout racing a refresh that already reached the server.** The refresh token captured for the server logout can already have been rotated, so the *new* token stays valid server-side (nobody holds it; it expires in ≤ 30 days). Closing this would need a "revoke all sessions for me" endpoint on the backend.
5. **Failed Keychain delete on logout** is only logged. If the delete fails the token survives and the user would be signed in again at the next launch. Very unlikely; a retry or a visible warning could be added.
6. The two fixes above (generation guard, read errors) have **no automated tests yet** (decision: features first, tests later). Good first tests when you add them: logout during a slow refresh writes nothing; a throwing `SecureStore.read` keeps the session.

---

## 8. Rules to keep when changing it

- Never call the refresh endpoint from anywhere except `runRefresh` (everything else must go through `performRefresh` so it stays single-flight).
- Never send a refresh token twice. Always overwrite it with the one in the latest response.
- Keep saving the new refresh token **before** publishing the new access token.
- Never clear the session for anything other than a 401 from `/refresh` (or an explicit logout).
- Keep `/api/auth/*` calls on the plain client without a Bearer token.
- Any `await` inside `runRefresh` can overlap with `clear()`: re-check `sessionGeneration` before writing state or announcing events.
- Don't use `try?` on Keychain reads where "missing" and "failed" must be told apart.
- New code should depend on `TokenProviding`, not on `TokenManager` directly.
