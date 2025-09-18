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
        // Ensure state exists only when actually marking activity
        ensureStateExists()
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
            // Fetch by deterministic ID to avoid arbitrary ordering and allow consolidation
            var descriptor = FetchDescriptor<StreakState>(predicate: #Predicate { $0.id == "streak_singleton" })
            descriptor.fetchLimit = 10
            let existing = try modelContext.fetch(descriptor)

            if existing.count > 1 {
                // Consolidate duplicates: choose highest streak, then most recent activity
                let bestRecord = existing.max { lhs, rhs in
                    if lhs.currentStreak != rhs.currentStreak {
                        return lhs.currentStreak < rhs.currentStreak
                    }
                    let lDate = lhs.lastActiveDay ?? .distantPast
                    let rDate = rhs.lastActiveDay ?? .distantPast
                    return lDate < rDate
                }

                if let bestRecord {
                    for rec in existing where rec !== bestRecord {
                        modelContext.delete(rec)
                    }
                    state = bestRecord
                    currentStreak = bestRecord.currentStreak
                    bestStreak = bestRecord.bestStreak
                    lastActiveDay = bestRecord.lastActiveDay
                    try modelContext.save()
                }
            } else if let first = existing.first {
                state = first
                currentStreak = first.currentStreak
                bestStreak = first.bestStreak
                lastActiveDay = first.lastActiveDay
            } else {
                // No record yet. Avoid creating immediately to give CloudKit a chance to sync it down.
                // We'll lazily create on first activity, and also attempt a delayed re-fetch.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                    do {
                        var retry = FetchDescriptor<StreakState>(predicate: #Predicate { $0.id == "streak_singleton" })
                        retry.fetchLimit = 1
                        let re = try modelContext.fetch(retry)
                        if let fetched = re.first {
                            self.state = fetched
                            self.currentStreak = fetched.currentStreak
                            self.bestStreak = fetched.bestStreak
                            self.lastActiveDay = fetched.lastActiveDay
                        }
                    } catch {
                        print("Streak delayed fetch error: \(error)")
                    }
                }
            }
        } catch {
            print("Streak load error: \(error)")
        }
    }

    /// Ensure a state exists before mutating; fetch again in case CloudKit just synced.
    private func ensureStateExists() {
        guard let modelContext else { return }
        if state != nil { return }
        do {
            var descriptor = FetchDescriptor<StreakState>(predicate: #Predicate { $0.id == "streak_singleton" })
            descriptor.fetchLimit = 1
            if let fetched = try modelContext.fetch(descriptor).first {
                state = fetched
                currentStreak = fetched.currentStreak
                bestStreak = fetched.bestStreak
                lastActiveDay = fetched.lastActiveDay
                return
            }
        } catch {
            // continue to create
        }

        let newState = StreakState()
        modelContext.insert(newState)
        state = newState
        do { try modelContext.save() } catch { print("Streak create error: \(error)") }
    }
}
