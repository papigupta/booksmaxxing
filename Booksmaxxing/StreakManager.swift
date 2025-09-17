import Foundation
import Combine
import SwiftData

final class StreakManager: ObservableObject {
    @Published private(set) var currentStreak: Int
    @Published private(set) var bestStreak: Int
    @Published private(set) var lastActiveDay: Date?
    @Published var isTestingActive: Bool = false

    // Persisted via SwiftData
    private var modelContext: ModelContext?
    private var state: StreakState?

    init() {
        self.currentStreak = 0
        self.bestStreak = 0
        self.lastActiveDay = nil
    }

    func attachModelContext(_ modelContext: ModelContext) {
        self.modelContext = modelContext
        loadOrCreateState()
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
        guard let modelContext else { return }
        if state == nil { state = StreakState() }
        state?.currentStreak = currentStreak
        state?.bestStreak = bestStreak
        state?.lastActiveDay = lastActiveDay
        // State is created and inserted in loadOrCreateState(); no re-insert needed here
        do { try modelContext.save() } catch { print("Streak persist error: \(error)") }
    }

    private func loadOrCreateState() {
        guard let modelContext else { return }
        do {
            let existing = try modelContext.fetch(FetchDescriptor<StreakState>())
            if let first = existing.first {
                state = first
                currentStreak = first.currentStreak
                bestStreak = first.bestStreak
                lastActiveDay = first.lastActiveDay
            } else {
                let newState = StreakState()
                modelContext.insert(newState)
                try modelContext.save()
                state = newState
                currentStreak = newState.currentStreak
                bestStreak = newState.bestStreak
                lastActiveDay = newState.lastActiveDay
            }
        } catch {
            print("Streak load error: \(error)")
        }
    }
}
