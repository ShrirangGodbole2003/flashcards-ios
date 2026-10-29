import Foundation
import UserNotifications

/// `UNUserNotificationCenter` implementation of `ReminderScheduling`.
struct UserNotificationReminderScheduler: ReminderScheduling {
    /// `userInfo` key that carries the deep link URL string. Read back by `NotificationTapHandler`.
    static let deepLinkKey = "deepLink"
    private static let identifierPrefix = "reminder.deck."

    private var center: UNUserNotificationCenter { .current() }

    func permission() async -> ReminderPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed        // authorized, provisional, ephemeral
        }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(_ reminder: DeckReminder, at date: Date) async throws {
        guard date.timeIntervalSinceNow > 1 else { throw ReminderError.timeInPast }

        let content = UNMutableNotificationContent()
        content.title = "Time to study"
        content.body = "\(reminder.deckTopic) · \(reminder.cardCount) \(reminder.cardCount == 1 ? "card" : "cards")"
        content.sound = .default
        content.threadIdentifier = "reminders"
        content.userInfo = [Self.deepLinkKey: DeepLink.deck(id: reminder.deckID).url.absoluteString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Same identifier replaces an earlier reminder for this deck.
        let request = UNNotificationRequest(identifier: Self.identifier(for: reminder.deckID),
                                            content: content,
                                            trigger: trigger)
        try await center.add(request)
    }

    func scheduledDate(forDeckID deckID: Int) async -> Date? {
        let identifier = Self.identifier(for: deckID)
        let pending = await center.pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == identifier }),
              let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
              date > Date() else { return nil }
        return date
    }

    func cancel(deckID: Int) {
        let identifier = Self.identifier(for: deckID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private static func identifier(for deckID: Int) -> String {
        identifierPrefix + String(deckID)
    }
}
