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
    private var previousStreakCount: Int
    private var previousLastActiveDay: Date?
    private var hasAttemptedReturningUserPrompt = false
    private let notificationScheduler = StreakNotificationScheduler.shared
    private let permissionManager = NotificationPermissionManager.shared

    init() {
        self.currentStreak = 0
        self.bestStreak = 0
        self.lastActiveDay = nil
        self.previousStreakCount = 0
        self.previousLastActiveDay = nil
    }

    func attachModelContext(_ modelContext: ModelContext) {
        self.modelContext = modelContext
        loadOrCreateState()
    }

    var isLitToday: Bool {
        guard let last = lastActiveDay else { return false }
        return Calendar.current.isDateInToday(last)
    }

    func refreshNotificationSchedule() {
        Task { [weak self] in
            guard let self else { return }
            await notificationScheduler.updateScheduledReminders(lastActiveDay: self.lastActiveDay)
        }
    }

    func resetForNewSession() {
        modelContext = nil
        state = nil
        currentStreak = 0
        bestStreak = 0
        lastActiveDay = nil
        previousStreakCount = 0
        previousLastActiveDay = nil
        hasAttemptedReturningUserPrompt = false
        Task { [notificationScheduler] in
            await notificationScheduler.cancelReminders()
        }
    }

    @discardableResult
    func markActivity(on date: Date = Date()) -> Bool {
        ensureStateExists()
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)

        if let last = lastActiveDay, cal.isDate(last, inSameDayAs: today) {
            return false
        }

        let priorStreakValue = currentStreak
        let priorLastActive = lastActiveDay
        let wasFirstRecordedSession = (priorStreakValue == 0 && priorLastActive == nil)

        previousStreakCount = priorStreakValue
        previousLastActiveDay = priorLastActive

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
        refreshNotificationSchedule()
        requestNotificationsAfterFirstSessionIfNeeded(wasFirstRecordedSession)
        return true
    }

    @discardableResult
    func resetTodayActivity() -> Bool {
        let cal = Calendar.current
        guard let last = lastActiveDay, cal.isDateInToday(last) else {
            return false
        }

        currentStreak = previousStreakCount
        lastActiveDay = previousLastActiveDay
        persist()
        refreshNotificationSchedule()
        return true
    }

    private func requestNotificationsAfterFirstSessionIfNeeded(_ wasFirstSession: Bool) {
        guard wasFirstSession else { return }
        permissionManager.requestAuthorizationIfNeeded(reason: .firstSession) { [weak self] granted in
            guard let self, granted else { return }
            self.refreshNotificationSchedule()
        }
    }

    private func persist() {
        guard let modelContext else { return }
        if state == nil { state = StreakState() }
        state?.currentStreak = currentStreak
        state?.bestStreak = bestStreak
        state?.lastActiveDay = lastActiveDay
        state?.previousStreakCount = previousStreakCount
        state?.previousLastActiveDay = previousLastActiveDay
        // State is created and inserted in loadOrCreateState(); no re-insert needed here
        do { try modelContext.save() } catch { print("Streak persist error: \(error)") }
    }

    private func loadOrCreateState() {
        guard let modelContext else { return }
        do {
            var descriptor = FetchDescriptor<StreakState>(predicate: #Predicate { $0.id == "streak_singleton" })
            descriptor.fetchLimit = 10
            let existing = try modelContext.fetch(descriptor)

            if existing.count > 1 {
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
                    bindState(bestRecord)
                    try modelContext.save()
                }
            } else if let first = existing.first {
                bindState(first)
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    do {
                        var retry = FetchDescriptor<StreakState>(predicate: #Predicate { $0.id == "streak_singleton" })
                        retry.fetchLimit = 1
                        let re = try modelContext.fetch(retry)
                        if let fetched = re.first {
                            self.bindState(fetched)
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

    private func bindState(_ newState: StreakState, triggerSideEffects: Bool = true) {
        state = newState
        currentStreak = newState.currentStreak
        bestStreak = newState.bestStreak
        lastActiveDay = newState.lastActiveDay
        previousStreakCount = newState.previousStreakCount
        previousLastActiveDay = newState.previousLastActiveDay
        guard triggerSideEffects else { return }
        evaluateReturningUserPromptIfNeeded()
        refreshNotificationSchedule()
    }

    private func evaluateReturningUserPromptIfNeeded() {
        guard !hasAttemptedReturningUserPrompt else { return }
        guard !permissionManager.hasPrompted else { return }
        guard currentStreak > 0 || lastActiveDay != nil else { return }
        hasAttemptedReturningUserPrompt = true
        permissionManager.requestAuthorizationIfNeeded(reason: .returningUser) { [weak self] granted in
            guard let self, granted else { return }
            self.refreshNotificationSchedule()
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
                bindState(fetched, triggerSideEffects: false)
                return
            }
        } catch {
            // continue to create
        }

        let newState = StreakState()
        modelContext.insert(newState)
        bindState(newState, triggerSideEffects: false)
        do { try modelContext.save() } catch { print("Streak create error: \(error)") }
    }
}
