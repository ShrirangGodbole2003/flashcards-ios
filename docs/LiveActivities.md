# Live Activity: study session progress

Shows the current session on the Lock Screen and in the Dynamic Island: deck name, "Card 5 of 12", progress bar, correct count, and a "done" state at the end. Status: built and compiles; **not yet verified on a device**.

## 1. Parts

| Piece | File | Target |
|---|---|---|
| Enable | root `Info.plist`: `NSSupportsLiveActivities = true` | app |
| Data model | `Shared/StudyActivityAttributes.swift` | app + widget |
| UI | `FlashcardsWidget/StudyLiveActivity.swift`, `StudyLockScreenBannerView.swift`, `StudyDynamicIslandViews.swift`, `StudyActivityComponents.swift` | widget |
| Contract | `Features/Study/Domain/StudyActivityControlling.swift` (+ `NoopStudyActivityController`) | app |
| ActivityKit code | `Core/LiveActivities/LiveStudyActivityController.swift` | app |
| Wiring | `StudyViewModel`, `StudyView`, `SessionStore`, `AppContainer`, `MainTabView`, `DecksTabView` | app |

The activity lives in the existing widget extension; `StudyLiveActivity()` is listed in `FlashcardsWidgetBundle`.

## 2. Data (`StudyActivityAttributes`)
- Fixed at start: `deckID`, `deckName`, `totalCards`.
- `ContentState` (changes per update): `answeredCount`, `correctCount`, `isFinished`.
- Helpers: `cardNumber(for:)` ("Card 5 of 12", capped at the total), `progress(for:)` (0...1).
- Keep it tiny: the system caps activity data at about 4 KB.

## 3. UI
- Lock Screen / banner: deck name, Studying/Done, progress bar, status text, correct count; light-blue tint.
- Dynamic Island: expanded (icon, correct count, deck name, bar + status), compact (icon + "5/12", check mark when done), minimal (progress ring). The island is always dark, so `Theme` resolves to dark variants.
- Tapping any presentation opens `flashcardsai://deck/<deckID>` (the existing deep link; deck detail).
- Xcode canvas previews exist for Lock Screen, Expanded, Compact and Minimal.

## 4. Lifecycle (who calls what)

| Moment | Call |
|---|---|
| `StudyView` appears | `viewModel.begin()` → `controller.start(...)` (guarded: once per appearance) |
| Card graded and user moves on (`next()`) | `controller.update(answeredCount:correctCount:)` |
| Last card done (`next()` finishes the session) | `controller.end(..., finished: true)`: "done" card stays 5 minutes |
| User leaves early (`onDisappear` → `didLeave()`) | `controller.end(..., finished: false)`: removed immediately |
| "Study again" (`restart()`) | `controller.start(...)` replaces the finished activity |
| App launch (`SessionStore.restore()`) | `controller.endAll()`: leftovers from a previous process |
| Sign-out / session expiry (`SessionStore.signOut()`) | `controller.endAll()` |

`begin()` is called from the view, not from `init`: the navigation destination closure can build the view model more than once, and each would start an activity.

## 5. `LiveStudyActivityController`
- Checks `ActivityAuthorizationInfo().areActivitiesEnabled` (the user can turn them off) and fails soft: errors are logged under the `liveactivity` category and studying is never affected.
- All operations go through one serial queue (`enqueue`): ActivityKit calls are `async` while callers are synchronous, and unordered tasks could show an older count.
- One activity at a time: `start` ends everything first.
- `staleDate` = 30 minutes after each update: if the app stops updating (killed), iOS marks the activity outdated.
- Updates are local (app running). Push-driven updates would need APNs and a backend, not built.

## 6. Manual checks
1. Settings → Face ID & Passcode (or Live Activities per app) must allow Live Activities for Flashcards.
2. Run on a device (Dynamic Island needs iPhone 14 Pro or newer; the Lock Screen banner works on any supported iPhone; the simulator shows both).
3. Start a session → lock the phone / go home → the activity shows "Card 1 of N".
4. Grade cards → the count and bar advance.
5. Finish → "x of N correct", dismissed after about 5 minutes.
6. Close the study screen mid-session → the activity disappears.
7. Tap the activity → the app opens the deck.
8. Log out mid-session / force-quit and reopen → no leftover activity.

## 7. Limits and ideas
- An activity runs for at most about 8 hours; fine for study sessions.
- Updates stop if iOS suspends the app, which is fine here since the user advances cards inside the app.
- Possible next steps: a sprint countdown with `Text(timerInterval:)`, tapping the activity to return to the current card (needs a study route), richer states.

## 8. Build recipe (the order we did it in)
1. Enable: `NSSupportsLiveActivities = true` in the root `Info.plist` (app target).
2. `Shared/StudyActivityAttributes.swift`: fixed attributes + small `ContentState` + helpers (`cardNumber`, `progress`).
3. UI in the widget extension: `ActivityConfiguration(for:)` with a Lock Screen view and a `DynamicIsland` (expanded regions, compact leading / trailing, minimal); `widgetURL` for taps; previews for each presentation; register in the widget bundle.
4. App side: `StudyActivityControlling` protocol + no-op default; `LiveStudyActivityController` (ActivityKit `request` / `update` / `end`, serial queue, fails soft); create it in `AppContainer`.
5. Wire it: `StudyViewModel` (`begin`, `next`, `restart`, `didLeave`), `StudyView` (`onAppear` / `onDisappear`), `SessionStore` (`endAll` on launch and sign-out), pass the controller down through `RootView` → `MainTabView` → `DecksTabView`.
6. Run a session on a device, lock the phone, check the banner / island / tap; document.

### How the data reaches the views
The app computes progress in `StudySession` and sends it with `activity.update(...)`. iOS stores the latest state and, whenever it must draw, runs the widget extension and passes `context.attributes` (fixed) and `context.state` (latest) into the `ActivityConfiguration` closures. The extension never reads app state.

### Behaviour worth knowing
The activity updates when the user moves on (`next()`), not when a card is answered, so it lags one card behind and "Card N of M" means the card currently being worked on. A possible change is to update on answer and show "x of N done".
