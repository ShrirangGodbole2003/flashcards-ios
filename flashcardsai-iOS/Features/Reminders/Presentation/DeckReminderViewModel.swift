import Foundation
import Observation

/// State behind the "Remind me" control on the deck detail screen.
@MainActor
@Observable
final class DeckReminderViewModel {
    struct QuickOption: Identifiable, Equatable {
        let id: String
        let title: String
        let date: Date
    }

    private(set) var scheduledDate: Date?
    private(set) var permission: ReminderPermission = .notDetermined
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    /// Filled in when the sheet opens, so the choices don't shift while it is on screen.
    private(set) var quickOptions: [QuickOption] = []
    /// Nil when too little of today is left to pick a time.
    private(set) var pickerRange: ClosedRange<Date>?

    var isPresentingSheet = false
    var customDate = Date()

    @ObservationIgnored private let summary: DeckSummary
    @ObservationIgnored private let scheduler: ReminderScheduling
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(summary: DeckSummary,
         scheduler: ReminderScheduling,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.summary = summary
        self.scheduler = scheduler
        self.now = now
        self.calendar = calendar
    }

    /// Refresh from the system (on appear, and when returning from Settings).
    func load() async {
        permission = await scheduler.permission()
        scheduledDate = await scheduler.scheduledDate(forDeckID: summary.id)
    }

    func presentSheet() {
        errorMessage = nil
        prepareChoices()
        isPresentingSheet = true
    }

    /// Schedules for a quick option or the custom time.
    func schedule(at date: Date) async {
        guard !isWorking else { return }
        guard date.timeIntervalSince(now()) > 1 else {
            errorMessage = "Pick a time later than now."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if await scheduler.permission() == .notDetermined {
            _ = await scheduler.requestPermission()
        }
        permission = await scheduler.permission()
        guard permission == .allowed else {
            errorMessage = "Notifications are turned off for Flashcards. Turn them on in Settings to get reminders."
            return
        }

        do {
            try await scheduler.schedule(DeckReminder(deckID: summary.id,
                                                      deckTopic: summary.topic,
                                                      cardCount: summary.cardCount),
                                         at: date)
            scheduledDate = await scheduler.scheduledDate(forDeckID: summary.id)
            isPresentingSheet = false
        } catch ReminderError.timeInPast {
            errorMessage = "Pick a time later than now."
        } catch {
            errorMessage = "Couldn't set the reminder. Please try again."
        }
    }

    func cancel() {
        scheduler.cancel(deckID: summary.id)
        scheduledDate = nil
    }

    // MARK: Choices (today only)

    private func prepareChoices() {
        let current = now()
        var options: [QuickOption] = []

        let inOneHour = current.addingTimeInterval(60 * 60)
        if calendar.isDate(inOneHour, inSameDayAs: current) {
            options.append(QuickOption(id: "hour", title: "In 1 hour", date: inOneHour))
        }
        if let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: current),
           evening.timeIntervalSince(current) > 60,
           abs(evening.timeIntervalSince(inOneHour)) > 15 * 60 {
            options.append(QuickOption(id: "evening", title: "This evening", date: evening))
        }
        quickOptions = options

        let earliest = current.addingTimeInterval(60)
        let latest = calendar.startOfDay(for: current).addingTimeInterval(24 * 60 * 60 - 60)   // 11:59 PM
        if earliest < latest {
            pickerRange = earliest...latest
            customDate = min(max(inOneHour, earliest), latest)
        } else {
            pickerRange = nil
        }
    }
}
