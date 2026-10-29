import SwiftUI
import os
import UserNotifications

@main
struct flashcardsai_iOSApp: App {
    private let container: AppContainer?
    private let configurationError: String?
    @State private var sessionStore: SessionStore?
    @State private var router: DeepLinkRouter
    // UNUserNotificationCenter keeps only a weak reference to its delegate.
    private let notificationHandler: NotificationTapHandler

    init() {
        // Created before anything else: a tap that launches the app is delivered once the delegate exists.
        let router = DeepLinkRouter()
        _router = State(initialValue: router)
        let handler = NotificationTapHandler { link in router.receive(link) }
        UNUserNotificationCenter.current().delegate = handler
        self.notificationHandler = handler

        do {
            let container = try AppContainer.live()
            self.container = container
            self.configurationError = nil
            _sessionStore = State(initialValue: container.makeSessionStore())
        } catch {
            self.container = nil
            self.configurationError = error.localizedDescription
        }
    }
 
    var body: some Scene {
        WindowGroup {
            Group {
                if let container, let sessionStore {
                    RootView(container: container, sessionStore: sessionStore)
                } else {
                    ConfigurationErrorView(message: configurationError ?? "The app could not start.")
                }
            }
            // Called by iOS when a flashcardsai:// URL opens the app (cold start or already running).
            .onOpenURL { url in handleDeepLink(url) }
            .environment(router)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else {
            Self.logger.debug("Ignored unsupported URL: \(url.absoluteString)")
            return
        }
        Self.logger.debug("Parsed deep link: \(String(describing: link))")
        router.receive(link)
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "flashcardsai", category: "deeplink")
}
