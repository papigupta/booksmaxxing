import Foundation
import Combine

final class StreakManager: ObservableObject {
    @Published private(set) var currentStreak: Int
    @Published private(set) var bestStreak: Int
    @Published private(set) var lastActiveDay: Date?
    @Published var isTestingActive: Bool = false

    private let currentKey = "streak_current"
    private let bestKey = "streak_best"
    private let lastDayKey = "streak_last_day"

    init() {
        let defaults = UserDefaults.standard
        self.currentStreak = defaults.integer(forKey: currentKey)
        self.bestStreak = defaults.integer(forKey: bestKey)
        if let date = defaults.object(forKey: lastDayKey) as? Date {
            self.lastActiveDay = date
        } else {
            self.lastActiveDay = nil
        }
        // Normalize: if there's a last day but current is 0, set to 1
        if lastActiveDay != nil && currentStreak == 0 {
            self.currentStreak = 1
        }
    }

    var isLitToday: Bool {
        guard let last = lastActiveDay else { return false }
        return Calendar.current.isDateInToday(last)
    }

    @discardableResult
    func markActivity(on date: Date = Date()) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)

        // If already marked today, no-op
        if let last = lastActiveDay, cal.isDate(last, inSameDayAs: today) {
            return false
        }

        if let last = lastActiveDay {
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            if cal.isDate(last, inSameDayAs: yesterday) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        lastActiveDay = today
        if currentStreak > bestStreak { bestStreak = currentStreak }
        persist()
        return true
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(currentStreak, forKey: currentKey)
        defaults.set(bestStreak, forKey: bestKey)
        defaults.set(lastActiveDay, forKey: lastDayKey)
        defaults.synchronize()
    }
}
