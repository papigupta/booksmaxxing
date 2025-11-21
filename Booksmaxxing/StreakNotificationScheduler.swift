import Foundation
import UserNotifications

final class StreakNotificationScheduler {
    static let shared = StreakNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let earlyIdentifier = "com.booksmaxxing.streak.early"
    private let lateIdentifier = "com.booksmaxxing.streak.late"

    private init() {}

    func updateScheduledReminders(lastActiveDay: Date?) async {
        let settings = await fetchSettings()
        guard isAuthorized(status: settings.authorizationStatus) else {
            await cancelReminders()
            return
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let targetDay: Date
        if let last = lastActiveDay, calendar.isDate(last, inSameDayAs: todayStart) {
            targetDay = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        } else {
            targetDay = todayStart
        }

        await scheduleReminders(for: targetDay)
    }

    func cancelReminders() async {
        center.removePendingNotificationRequests(withIdentifiers: [earlyIdentifier, lateIdentifier])
    }

    private func scheduleReminders(for dayStart: Date) async {
        await cancelReminders()
        var requests: [UNNotificationRequest] = []
        let now = Date()

        if let earlyDate = makeDate(for: dayStart, hour: 10, minute: 15), earlyDate > now {
            requests.append(makeRequest(
                identifier: earlyIdentifier,
                fireDate: earlyDate,
                title: "Keep Your Streak Going",
                body: "Drop in for a quick lesson before the day ramps up."
            ))
        }

        if let lateDate = makeDate(for: dayStart, hour: 19, minute: 30), lateDate > now {
            requests.append(makeRequest(
                identifier: lateIdentifier,
                fireDate: lateDate,
                title: "Don't Break Your Streak",
                body: "There's still time today—finish a lesson to keep the flame lit."
            ))
        }

        guard !requests.isEmpty else { return }
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                print("Streak notification scheduling failed: \(error)")
            }
        }
    }

    private func makeDate(for dayStart: Date, hour: Int, minute: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps)
    }

    private func makeRequest(identifier: String, fireDate: Date, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func fetchSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    private func isAuthorized(status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}
