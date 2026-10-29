import Foundation
import UserNotifications

/// Receives notification taps and shows banners while the app is open.
///
/// `UNUserNotificationCenter.delegate` is a weak reference, so whoever creates this must keep it alive,
/// and must set it early at launch: a tap that launches the app is delivered as soon as the delegate exists.
///
/// The completion-handler variants are used on purpose. With the `async` variants the system calls the
/// completion handler from whatever thread the task finished on, and UIKit then crashes with
/// "Call must be made on main thread" (it updates the app snapshot inside that completion).
final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {
    private let onDeepLink: @MainActor (DeepLink) -> Void

    init(onDeepLink: @escaping @MainActor (DeepLink) -> Void) {
        self.onDeepLink = onDeepLink
    }

    /// The user tapped the notification (not an action button).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = Self.deepLink(from: response)
        // Always finish on the main thread, after the router has the link.
        DispatchQueue.main.async { [onDeepLink] in
            if let link { MainActor.assumeIsolated { onDeepLink(link) } }
            completionHandler()
        }
    }

    /// The notification fired while the app is in the foreground: show it anyway.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            completionHandler([.banner, .list, .sound])
        }
    }

    // Same validation as any other incoming URL.
    private static func deepLink(from response: UNNotificationResponse) -> DeepLink? {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let text = response.notification.request.content.userInfo[UserNotificationReminderScheduler.deepLinkKey] as? String,
              let url = URL(string: text) else { return nil }
        return DeepLink(url: url)
    }
}
