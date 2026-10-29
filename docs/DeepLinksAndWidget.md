# Deep links, routing and the home-screen widget

How a URL becomes a screen, and how the widget produces those URLs. Status: deep links and the widget are built and compile; **not yet verified on a device** (see "Manual checks").

## 1. Big picture

```
 outside the app                         inside the app
 ───────────────                         ──────────────
 widget tap ─┐
 (later: notification tap, Shortcut)     .onOpenURL ─► DeepLink(url:) ─► DeepLinkRouter ─► tab / path state ─► SwiftUI
 Safari / simctl openurl ─┘                              parse+validate    pending → apply
```

- Two different enums, on purpose:
  - `DeepLink` (`Shared/DeepLink.swift`): what a URL *means*. Carries only ids.
  - `DecksRoute` (`Features/Decks/Presentation/DecksTabView.swift`): a screen in the Decks `NavigationStack`. Carries loaded data (`DeckSummary`, `Deck`).
- `DeepLinkRouter` (`App/DeepLinkRouter.swift`) translates the first into the second by writing the **same state** the UI is bound to. It never pushes a view.

## 2. URLs

| URL | Result |
|---|---|
| `flashcardsai://decks` | Decks tab, stack reset to the list |
| `flashcardsai://deck/42` | Decks tab, deck 42's detail screen, **only if deck 42 is in the already loaded list** |
| `flashcardsai://score` | Score tab |
| `flashcardsai://profile` | Profile tab |

`DeepLink.init?(url:)` is a failable initializer: wrong scheme, unknown host, wrong number of path segments, or a non-positive / non-numeric id → `nil`. Input from outside the app is untrusted, so nothing else ever sees a raw URL. `DeepLink.url` builds the URL for widgets/notifications; `DeepLink(url: link.url) == link`.

A custom scheme puts the first word after `://` in `URL.host` (`deck` in `flashcardsai://deck/42`) and the rest in the path (`/42`).

## 3. Registration (`Info.plist`)

The project generates its Info.plist (`GENERATE_INFOPLIST_FILE = YES`). The root-level `Info.plist` holds only `CFBundleURLTypes` (scheme `flashcardsai`); `INFOPLIST_FILE = Info.plist` on the app target makes Xcode merge it into the generated one. It sits outside the synced source folder so it isn't also copied as a resource. Keep the scheme in sync with `DeepLink.scheme`.

## 4. Receiving the URL

`flashcardsai_iOSApp` puts `.onOpenURL` on the window's root content (inside `WindowGroup`, wrapped in a `Group`, because it is a view modifier). It fires for cold starts and for a running app, for custom schemes and universal links. One handler at the root is deliberate: it always exists (unlike views that only appear after sign-in) and can't fire twice.

## 5. `DeepLinkRouter`

`@Observable @MainActor`, created once in the app and passed with `.environment(router)`.

- State: `selectedTab`, `decksPath` (`[DecksRoute]`), `pendingLink`, `notice`.
- `receive(_:)` only stores the link. A newer link replaces an unapplied one.
- `applyPending(decks:)` does the routing. `decks == nil` means "list not loaded yet": a deck link then stays pending.
- Deck links never fetch. If the id isn't in the loaded list the router sets `notice` ("That deck isn't available on this device.") and `MainTabView` shows an alert. The backend remains the authority on ownership.
- `reset()` clears everything. `RootView` calls it only on **signedIn → signedOut**, not at launch, so a link that opened the app while signed out survives until login.

UI binding:
- `MainTabView`: `TabView(selection: $router.selectedTab)`.
- `DecksTabView`: `NavigationStack(path: $router.decksPath)`. It calls `router.applyPending(...)` on appear, when `pendingLink` changes, and when `listViewModel.hasLoaded` changes.

## 6. Signed-out and cold-start behaviour

1. Link arrives → stored as `pendingLink` (state `.launching` / `.signedOut`).
2. Nothing consumes it: the screens that apply links don't exist yet.
3. User signs in → `MainTabView` appears → `DecksTabView` applies it (deck links wait for the list).

The link carries no account information, so after a *different* user signs in the deck simply isn't in their list and the alert appears. Sharing a deck with another person would need a backend share token (not built).

Known gaps: a pending link never expires; a deck link stays pending if the first list load fails.

Switching tabs via a link leaves other tabs' stacks as they were (standard iOS). To reset them, clear their paths in `applyPending`.

## 7. Adding a deep-linkable inner screen

1. Add a case to the tab's route enum and register it with `.navigationDestination(for:)`.
2. Bind that tab's `NavigationStack` to a path property on the router; clear it in `reset()`.
3. Add a `DeepLink` case, a parser rule, and a `url` case.
4. Handle it in `applyPending` (set `selectedTab` and the path). Non-deep-linkable screens keep a local `@State` path.

## 8. The widget

### Why a snapshot
A widget is a separate extension process: no access to app memory, view models or the Keychain tokens. The app therefore writes a tiny JSON snapshot into an **App Group** (`group.com.flashcardsai.flashcardsai-iOS`, `Shared/AppGroup.swift`; capability on both targets, entitlements files at the project root / app folder) and the widget reads it.

### Shared code (`Shared/`, compiled into both targets)
`AppGroup`, `DeepLink`, `Theme`, `WidgetSnapshot` (`WidgetDeck`, `WidgetSnapshot`, `WidgetSnapshotStoring`, `AppGroupSnapshotStore`). `Shared` is a synced root group added to both targets in the project file.

### App side
- `DeckSnapshotPublishing` (Domain protocol) with `NoopDeckSnapshotPublisher` for previews/tests.
- `WidgetSnapshotPublisher` (`Core/Widgets`): keeps the newest 5 decks, saves, then `WidgetCenter.reloadAllTimelines()`. Skips both when nothing changed.
- `DeckListViewModel` publishes after each successful fetch and after `insert`.
- `SessionStore.signOut()` (the single path to `.signedOut`) clears the snapshot so a previous account's deck names never stay on the home screen.

### Widget side (`FlashcardsWidget/`)
- `Provider` (`TimelineProvider`): reads the snapshot; one entry, `policy: .never` (the app triggers reloads).
- Small: newest deck, "Start" pill; whole widget is `widgetURL(DeepLink.deck(id:).url)`.
- Large (not medium: a medium widget is too short for a header plus several rows): up to 5 rows, each a `Link` to its deck; taps elsewhere open the deck list.
- Empty (signed out / no decks): "No decks yet", links to `flashcardsai://decks`.
- Styling from `Theme` (light/dark), `containerBackground(for: .widget)`, combined accessibility elements.

A tap runs the normal path: `.onOpenURL` → router → pending → applied once signed in and the list has loaded.

## 9. Manual checks
1. Run the **flashcardsai-iOS** scheme on a simulator/device, sign in, open Decks.
2. Home screen → long-press → **+** → Flashcards → add small and large.
3. Tap the widget / a row → the deck's detail opens. Tap an empty area of the large widget → deck list.
4. Log out → the widget shows "No decks yet".
5. Terminal: `xcrun simctl openurl booted "flashcardsai://score"`, `.../deck/<id>`, `.../deck/99999` (alert), `.../deck/abc` (ignored, check the `deeplink` log category).
6. Signed out: open `flashcardsai://score`, then sign in → Score tab.

## 10. Ideas / limitations
- Widget shows the newest deck; "last studied" or a user-chosen deck (App Intents configuration) is a later step.
- Link to start studying directly (needs the full deck; the detail screen fetches it).
- Pending-link expiry and clearing on a failed list load.
- Local notifications can reuse everything: put `DeepLink.url` in `userInfo` and call `router.receive` from the notification delegate.
- Universal links need a domain, an `apple-app-site-association` file and the Associated Domains capability.

## 11. Build recipe (the order we did it in)

**Deep links**
1. `Shared/DeepLink.swift`: enum of destinations + failable `init?(url:)` (validate scheme, host, segment count, id) + `url`.
2. Root `Info.plist` with `CFBundleURLTypes`; set `INFOPLIST_FILE = Info.plist` on the app target (merged with the generated plist; keep the file outside the synced source folder).
3. `.onOpenURL` on the window's root content → `DeepLink(url:)` → `router.receive`.
4. `App/DeepLinkRouter.swift`: `selectedTab`, `decksPath`, `pendingLink`, `notice`, `applyPending(decks:)`, `reset()`.
5. UI binds to the router: `TabView(selection: $router.selectedTab)`, `NavigationStack(path: $router.decksPath)`; `DecksTabView` calls `applyPending` on appear / link change / list loaded; alert for `notice`; `RootView` resets on signedIn → signedOut.
6. Check with `xcrun simctl openurl booted "flashcardsai://..."`, then document.

**Widget**
1. Xcode: File → New → Target → Widget Extension (`FlashcardsWidget`); remove the template Control / Live Activity / intent files you don't need.
2. App Groups capability (`group.com.flashcardsai.flashcardsai-iOS`) on both targets; the id lives in `Shared/AppGroup.swift` and in both entitlements files.
3. `Shared/` folder (synced root group added to both targets): `DeepLink`, `Theme`, `WidgetSnapshot` (model + App Group store).
4. App side: `DeckSnapshotPublishing` protocol, `WidgetSnapshotPublisher` (save + `reloadAllTimelines`, skip if unchanged), called from `DeckListViewModel`; `SessionStore.signOut()` clears.
5. Widget side: `TimelineProvider` reading the snapshot, views per family (small / large), `widgetURL` / `Link` with `DeepLink.url`, empty state, `containerBackground`.
6. Run the app, add the widget from the gallery, tap it; document.
