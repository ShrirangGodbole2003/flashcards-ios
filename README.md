# Flashcards AI (iOS)

An iOS flashcards app built with **SwiftUI**. Pick any topic and difficulty, and an AI-generated deck is ready to study with interactive flip cards, a home-screen widget, Live Activities and deep links.

The app talks to a Spring Boot + PostgreSQL backend that uses Google Gemini to generate the cards.
Backend repo: `<link to backend repo>`

## Demo

> Videos coming soon. Drop the files or links into the sections below.

| Feature | Video |
|---|---|
| Sign up, log in, session restore | _add video_ |
| Generate a deck with AI | _add video_ |
| Study mode (flip cards, gestures, summary) | _add video_ |
| Home-screen widget | _add video_ |
| Live Activity / Dynamic Island | _add video_ |
| Deep links and deck reminders | _add video_ |

## Features

- **Accounts:** register, log in, log out, and stay signed in across launches.
- **AI-generated decks:** enter a topic and a difficulty (Beginner, Intermediate, Advanced) and get a deck of Q&A, multiple-choice and True/False cards.
- **Study mode:** animated flip cards, drag to flip and swipe to grade Q&A cards, hints, haptics, progress bar, and a results summary with a review of missed cards.
- **Scores:** per-account history and stats, stored on the device.
- **Widget:** a WidgetKit home-screen widget (small and large) showing your latest decks.
- **Live Activities:** study progress on the Lock Screen and in the Dynamic Island.
- **Deep links:** `flashcardsai://` links open a deck or tab directly, from widget taps and notifications.
- **Reminders:** schedule a local notification for a deck that opens it when tapped.
- **Accessibility:** Dynamic Type, VoiceOver labels, Reduce Motion, light and dark mode.

## Tech stack

| Area | Choice |
|---|---|
| UI | SwiftUI, Observation (`@Observable`) |
| Concurrency | async/await, actors, structured concurrency |
| Networking | `URLSession` only, no third-party packages |
| Secure storage | Keychain |
| System features | WidgetKit, ActivityKit, UserNotifications, App Groups |
| Testing | Swift Testing |
| Minimum iOS | 18.5 |

## Architecture

MVVM with clean architecture. Dependencies point inward, and view models depend on protocols, never on networking or the Keychain.

```
Presentation (Views, ViewModels)  ──▶  Domain (models, repository protocols, pure logic)
                                            ▲
Data (DTOs, remote/local sources, repositories) ──┘ implements
```

```
flashcardsai-iOS/
  App/          app entry, root view, tabs, session store, deep link router
  Core/         networking, token management, Keychain, config, design system, DI
  Features/     Auth · Decks · Study · Score · Profile · Reminders
                (each with Domain / Data / Presentation)
Shared/         code shared by the app and the widget (theme, deep links, App Group)
FlashcardsWidget/   widget and Live Activity extension
flashcardsai-iOSTests/   unit tests
```

Highlights:

- **Composition root:** `AppContainer` is the only place that creates concrete types.
- **Auth and tokens:** short-lived JWT access tokens are kept in memory. The rotating refresh token is kept in the Keychain. An actor-based `TokenManager` shares a single refresh request between concurrent callers, retries a rejected request once, and logs the user out only on a definitive refresh rejection, never because the device is offline.
- **Networking:** `AuthorizedHTTPClient` decorates the base client to add the Bearer header, and auth endpoints never receive one. Errors from the backend are RFC 9457 problem details decoded into a typed `APIError`.
- **Testability:** protocol-based repositories and test doubles let view models, the token manager and the networking layer be unit tested without a server.

More detail is in [`DOCUMENTATION.md`](DOCUMENTATION.md) and the [`docs/`](docs) folder.

## Getting started

### Requirements

- Xcode with the iOS 18.5 SDK or newer
- The backend running locally (see the backend repo for setup)

### Run the app

1. Clone the repo and open `flashcardsai-iOS.xcodeproj` in Xcode.
2. Select the `flashcardsai-iOS` scheme.
3. In **Signing & Capabilities**, choose your own team for the app and the widget targets. Both targets use the App Groups capability, so change the group identifier to one under your account if needed (in `Shared/AppGroup.swift` and both `.entitlements` files).
4. Run on a simulator or device. Use a signed build so the Keychain works.


### Run the tests

```bash
xcodebuild test -project flashcardsai-iOS.xcodeproj -scheme flashcardsai-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:flashcardsai-iOSTests
```

