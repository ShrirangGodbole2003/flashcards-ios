import Foundation

enum ReminderPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

/// What a reminder says and where it leads. The scheduler turns it into a notification whose tap
/// opens `flashcardsai://deck/<deckID>`.
struct DeckReminder: Equatable, Sendable {
    let deckID: Int
    let deckTopic: String
    let cardCount: Int
}

enum ReminderError: Error, Equatable {
    case timeInPast
}

/// Schedules a one-off "time to study this deck" local notification. View models depend on this
/// protocol only, so they never import UserNotifications.
protocol ReminderScheduling: Sendable {
    func permission() async -> ReminderPermission
    /// Shows the system prompt (only the first time). Returns whether notifications are now allowed.
    func requestPermission() async -> Bool
    /// One reminder per deck: scheduling again replaces the previous one.
    func schedule(_ reminder: DeckReminder, at date: Date) async throws
    /// When the deck's reminder will fire, or nil if none is pending.
    func scheduledDate(forDeckID deckID: Int) async -> Date?
    func cancel(deckID: Int)
    /// Removes every pending and already delivered reminder. Called on sign-out.
    func cancelAll()
}

/// Default for previews and tests.
struct NoopReminderScheduler: ReminderScheduling {
    func permission() async -> ReminderPermission { .allowed }
    func requestPermission() async -> Bool { true }
    func schedule(_ reminder: DeckReminder, at date: Date) async throws {}
    func scheduledDate(forDeckID deckID: Int) async -> Date? { nil }
    func cancel(deckID: Int) {}
    func cancelAll() {}
}
