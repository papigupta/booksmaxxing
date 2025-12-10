import Foundation
import SwiftData

@MainActor
final class UserAnalyticsService {
    static let shared = UserAnalyticsService()

    private let defaults = UserDefaults.standard
    private let guestIdKey = "analytics.guestUserId"
    private var starterBookIds: Set<String> = []

    private var modelContext: ModelContext?
    private var snapshot: UserAnalyticsSnapshot?
    private var activeUserId: String?
    private var pendingSaveTask: Task<Void, Never>?
    private var isGuestSession = true

    private init() {
        starterBookIds = loadStarterBookIds()
    }

    func attachModelContext(_ context: ModelContext) {
        modelContext = context
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        if let currentUserId = activeUserId {
            loadOrCreateSnapshot(for: currentUserId)
        }
    }

    func updateAuthState(userIdentifier: String?, isSignedIn: Bool, isGuestSession: Bool) {
        self.isGuestSession = isGuestSession
        let resolvedId = userIdentifier ?? resolveGuestIdentifier()
        if resolvedId != activeUserId {
            activeUserId = resolvedId
            snapshot = nil
            loadOrCreateSnapshot(for: resolvedId)
        }
        if isSignedIn && !isGuestSession {
            markSignedInIfNeeded()
        }
    }

    func recordAppLaunch(version: String) {
        updateSnapshot { snapshot in
            snapshot.appVersionLastSeen = version
        }
    }

    func markEmail(status: EmailStatus, hasEmail: Bool) {
        updateSnapshot { snapshot in
            let now = Date()
            snapshot.emailStatus = status
            if hasEmail { snapshot.hasEmail = true }
            snapshot.emailUpdatedAt = now
        }
    }

    func refreshBookStats() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Book>()
        let books = (try? context.fetch(descriptor)) ?? []
        let starterCount = books.reduce(0) { count, book in
            guard let googleBooksId = book.googleBooksId else { return count }
            return starterBookIds.contains(googleBooksId) ? count + 1 : count
        }
        updateSnapshot { snapshot in
            if !books.isEmpty { snapshot.hasAddedBook = true }
            snapshot.starterLessonBookCount = starterCount
        }
    }

    func markLessonStarted(book: Book?) {
        let isStarter = isStarterBook(book)
        updateSnapshot { snapshot in
            if !snapshot.startedLesson {
                snapshot.startedLesson = true
                snapshot.firstLessonStartedAt = Date()
            }
            if isStarter && !snapshot.usedStarterLesson {
                snapshot.usedStarterLesson = true
                snapshot.starterLessonFirstUsedAt = Date()
            }
        }
    }

    func markLessonFinished() {
        updateSnapshot { snapshot in
            if !snapshot.finishedLesson {
                snapshot.finishedLesson = true
                snapshot.firstLessonFinishedAt = Date()
            }
        }
    }

    func markResultsViewed() {
        updateSnapshot { snapshot in
            snapshot.resultsViewed = true
            snapshot.resultsLastViewedAt = Date()
        }
    }

    func markPrimerOpened() {
        updateSnapshot { snapshot in
            if !snapshot.primerOpened {
                snapshot.primerOpened = true
                snapshot.primerFirstOpenedAt = Date()
            }
        }
    }

    func markStreakPageViewed() {
        updateSnapshot { snapshot in
            snapshot.streakPageViewed = true
            snapshot.streakPageLastViewedAt = Date()
        }
    }

    func markActivityRingsViewed() {
        updateSnapshot { snapshot in
            snapshot.activityRingsViewed = true
            snapshot.activityRingsLastViewedAt = Date()
        }
    }

    func updateStreak(current: Int, best: Int, litToday: Bool) {
        updateSnapshot { snapshot in
            snapshot.currentStreak = current
            snapshot.bestStreak = max(snapshot.bestStreak, best)
            snapshot.streakLitToday = litToday
        }
    }

    func updateRingClosures(brainCaloriesClosed: Bool, clarityClosed: Bool, attentionClosed: Bool) {
        updateSnapshot { snapshot in
            if brainCaloriesClosed { snapshot.brainCaloriesRingClosed = true }
            if clarityClosed { snapshot.clarityRingClosed = true }
            if attentionClosed { snapshot.attentionRingClosed = true }
        }
    }

    // MARK: - Private Helpers

    private func markSignedInIfNeeded() {
        updateSnapshot { snapshot in
            if snapshot.signedInAt == nil {
                snapshot.signedInAt = Date()
            }
        }
    }

    private func resolveGuestIdentifier() -> String {
        if let existing = defaults.string(forKey: guestIdKey) {
            return existing
        }
        let newId = "guest-\(UUID().uuidString)"
        defaults.set(newId, forKey: guestIdKey)
        return newId
    }

    private func isStarterBook(_ book: Book?) -> Bool {
        guard
            let googleBooksId = book?.googleBooksId,
            starterBookIds.contains(googleBooksId)
        else { return false }
        return true
    }

    private func loadStarterBookIds() -> Set<String> {
        guard let seeds = try? StarterLibrary.shared.books() else { return [] }
        return Set(seeds.map { $0.starterId })
    }

    private func loadOrCreateSnapshot(for userId: String) {
        guard let context = modelContext else { return }
        do {
            var descriptor = FetchDescriptor<UserAnalyticsSnapshot>(
                predicate: #Predicate { $0.id == userId }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                snapshot = existing
                existing.userIdentifier = userId
                existing.lastUpdatedAt = Date()
            } else {
                let now = Date()
                let newSnapshot = UserAnalyticsSnapshot(id: userId, userIdentifier: userId, firstSeenAt: now)
                context.insert(newSnapshot)
                snapshot = newSnapshot
                try context.save()
            }
        } catch {
            print("UserAnalyticsService load error: \(error)")
        }
    }

    private func updateSnapshot(_ changes: (UserAnalyticsSnapshot) -> Void) {
        guard let snapshot = ensureSnapshot() else { return }
        changes(snapshot)
        snapshot.lastUpdatedAt = Date()
        scheduleSave()
    }

    private func ensureSnapshot() -> UserAnalyticsSnapshot? {
        if let snapshot {
            return snapshot
        }
        guard let userId = activeUserId else { return nil }
        loadOrCreateSnapshot(for: userId)
        return snapshot
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self?.saveNow()
        }
    }

    private func saveNow() {
        guard let context = modelContext else { return }
        do {
            try context.save()
            if let snapshot {
                let payload = AnalyticsPublicRecordPayload(snapshot: snapshot, isGuestSession: isGuestSession)
                AnalyticsPublicSyncService.shared.enqueueSync(payload)
            }
        } catch {
            print("UserAnalyticsService save error: \(error)")
        }
    }
}
