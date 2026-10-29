# Notifications: "Remind me" for a deck

A local notification the user schedules from the deck detail screen. Tapping it opens that deck through the deep link router. Status: built and compiles; **not yet verified on a device**.

## 1. User flow
1. Deck detail → **Remind me today**.
2. Sheet: quick choices ("In 1 hour", "This evening" = 8 PM) or a time picker. Today only.
3. First time: iOS shows the notification permission prompt. If denied, the sheet explains and offers **Open Settings**.
4. A one-off local notification is scheduled: "Time to study / Swift Concurrency · 12 cards".
5. The detail screen now shows **Reminder set · 8:00 PM** with **Change** and **Cancel**.
6. The notification fires. Tapping it opens `flashcardsai://deck/<id>` → deck detail (see `docs/DeepLinksAndWidget.md`).

## 2. Parts

| Piece | File |
|---|---|
| Contract (`ReminderScheduling`, `DeckReminder`, `ReminderPermission`, `NoopReminderScheduler`) | `Features/Reminders/Domain/ReminderScheduling.swift` |
| `UNUserNotificationCenter` implementation | `Core/Notifications/UserNotificationReminderScheduler.swift` |
| Tap + foreground handling | `Core/Notifications/NotificationTapHandler.swift` |
| State / rules | `Features/Reminders/Presentation/DeckReminderViewModel.swift` |
| UI | `DeckReminderSection.swift`, `RemindMeSheet.swift` (same folder), used by `DeckDetailView` |
| Wiring | `AppContainer`, `RootView`, `MainTabView`, `DecksTabView`, `SessionStore`, `flashcardsai_iOSApp` |

## 3. Scheduling (`UserNotificationReminderScheduler`)
- Content: title "Time to study", body `topic · N cards`, default sound, `threadIdentifier = "reminders"`, `userInfo["deepLink"] = DeepLink.deck(id:).url.absoluteString`.
- Trigger: `UNCalendarNotificationTrigger` for the chosen date (non-repeating).
- Identifier: `reminder.deck.<deckID>`: one reminder per deck; scheduling again replaces it.
- `scheduledDate(forDeckID:)` reads the pending requests (`nextTriggerDate`), so the "Reminder set" label always reflects the system, even after a relaunch.
- Refuses a time that is not in the future (`ReminderError.timeInPast`).
- `permission()` maps authorized / provisional / ephemeral to `.allowed`.

## 4. Tapping a notification
- `NotificationTapHandler` is the `UNUserNotificationCenterDelegate`. It is created in `flashcardsai_iOSApp.init` together with the router and assigned immediately: the center holds only a **weak** reference (the app keeps the handler in a property) and a tap that launches the app is delivered as soon as a delegate exists.
- `didReceive`: reads `userInfo["deepLink"]`, runs it through `DeepLink(url:)` (same validation as any URL) and calls `router.receive(link)`.
- From there it is the normal pending-link flow: waits for sign-in and for the deck list, then opens the deck, or shows "That deck isn't available on this device."
- `willPresent`: banners and sound are shown even while the app is open.
- Both delegate methods use the **completion-handler** variants and call the handler on the main queue. The `async` variants crashed on a device/simulator tap with `NSInternalInconsistencyException: Call must be made on main thread` (UIKit updates the app snapshot inside the completion handler, and the async bridge can call it from a background thread).

## 5. View model rules (`DeckReminderViewModel`)
- Choices are computed when the sheet opens: "In 1 hour" only if it is still today; "This evening" only if 8 PM is more than a minute away and not about the same time as the first option; picker range = now + 1 min ... 11:59 PM, absent late at night.
- `schedule(at:)`: rejects past times, asks for permission only when `.notDetermined`, schedules, refreshes `scheduledDate`, closes the sheet. Permission denied → message and `permission == .denied` (sheet shows **Open Settings**).
- `DeckDetailView` reloads state on appear and whenever the scene becomes active (returning from Settings, or a reminder that fired meanwhile).

## 6. Sign-out
`SessionStore.signOut()` (the single path to `.signedOut`: logout, expired session, no stored session at launch) calls `reminderScheduler.cancelAll()`, which removes **pending and already delivered** reminders. Reasons: reminders contain deck names of the account that left (visible on the lock screen of a shared phone), and another account could not open those decks anyway. Side effect: a user whose session expired and who signs back in must set reminders again. A delivered reminder tapped by a different account opens nothing but the existing "isn't available" alert.

## 7. Manual checks
1. Open a deck → **Remind me today** → "In 1 hour" or a custom time a minute away. Allow notifications.
2. The row shows **Reminder set**. Change it, cancel it, set it again.
3. Lock the phone / background the app; when it fires, tap it → the app opens on that deck.
4. Kill the app, wait for a reminder, tap it → cold start opens the deck after the list loads.
5. Tap it while signed out → login first, then the deck.
6. Deny permission (Settings) → the sheet explains and **Open Settings** works; enable and return → scheduling works.
7. Set a reminder, log out → it never fires; Notification Center is empty.
8. App open when it fires → banner shown.

## 8. Limits and ideas
- Reminders are one-off and per deck; no daily schedule, no settings screen yet.
- Notification text is plain; no action buttons (e.g. "Start now").
- Ideas: daily reminder with a time in Profile (`flashcardsai://profile/notifications`), streak / inactivity nudges (needs last-study dates), "review missed cards" (needs missed ids), remote push for "deck ready" (needs APNs and the backend).

## 9. Build recipe (the order we did it in)
1. `ReminderScheduling` protocol + `NoopReminderScheduler`.
2. `UserNotificationReminderScheduler` (permission, schedule with deep link in `userInfo`, query, cancel).
3. `NotificationTapHandler` + early delegate assignment in the app's `init`, feeding `router.receive`.
4. `DeckReminderViewModel` (choices, permission, schedule, cancel).
5. `DeckReminderSection` + `RemindMeSheet`, added to `DeckDetailView`.
6. Create the scheduler in `AppContainer` and pass it down (`RootView` → `MainTabView` → `DecksTabView` → `DeckDetailView`); `SessionStore` cancels all on sign-out.
7. Run on a device, test the checklist, document.
