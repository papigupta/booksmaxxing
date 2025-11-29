import Foundation
import FirebaseAnalytics

enum BMEvent {
    case appOpened
    case bookAdded(bookId: String, source: BookSource)
    case sessionStarted(bookId: String)
    case sessionCompleted(bookId: String, duration: TimeInterval, numQuestions: Int)
    case questionAnswered(
        bookId: String,
        questionType: QuestionTypeMetric,
        queueType: QueueTypeMetric,
        correct: Bool,
        difficulty: QuestionDifficultyMetric
    )
    case starterLibrarySeeded(bookCount: Int)
    case starterLibrarySeedingFailed(reason: String)
}

enum BookSource: String {
    case manual
    case suggested
}

enum QuestionTypeMetric: String {
    case mcq
    case open
}

enum QueueTypeMetric: String {
    case fresh
    case review
    case spfu
    case curveball
}

enum QuestionDifficultyMetric: String {
    case easy
    case medium
    case hard
}

final class AnalyticsManager {
    static let shared = AnalyticsManager()

    var totalSessionsCompleted: Int { defaults.integer(forKey: Keys.totalSessionsCompleted) }
    var booksAdded: Int { defaults.integer(forKey: Keys.booksAdded) }
    var uniqueDaysUsed: Int { Set(defaults.stringArray(forKey: Keys.uniqueDays) ?? []).count }

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.booksmaxxing.analytics")
    private var hasLoggedAppOpenThisLaunch = false

    private init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    func track(_ event: BMEvent) {
        queue.async {
            guard self.shouldLog(event) else { return }
            let payload = self.payload(for: event)
            Analytics.logEvent(payload.name, parameters: payload.parameters)
            self.updateLocalCounters(for: event)
        }
    }

    private func shouldLog(_ event: BMEvent) -> Bool {
        switch event {
        case .appOpened:
            guard !hasLoggedAppOpenThisLaunch else { return false }
            hasLoggedAppOpenThisLaunch = true
            return true
        default:
            return true
        }
    }

    private func payload(for event: BMEvent) -> (name: String, parameters: [String: Any]?) {
        switch event {
        case .appOpened:
            return ("app_opened", nil)
        case let .bookAdded(bookId, source):
            return ("book_added", ["book_id": bookId, "source": source.rawValue])
        case let .sessionStarted(bookId):
            return ("session_started", ["book_id": bookId])
        case let .sessionCompleted(bookId, duration, numQuestions):
            var params: [String: Any] = [
                "book_id": bookId,
                "duration_seconds": max(0, Int(duration)),
                "num_questions": numQuestions
            ]
            params["is_first_session"] = isFirstSessionCompletion()
            return ("session_completed", params)
        case let .questionAnswered(bookId, questionType, queueType, correct, difficulty):
            return (
                "question_answered",
                [
                    "book_id": bookId,
                    "question_type": questionType.rawValue,
                    "queue_type": queueType.rawValue,
                    "correct": NSNumber(value: correct),
                    "difficulty": difficulty.rawValue
                ]
            )
        case let .starterLibrarySeeded(bookCount):
            return ("starter_library_seeded", ["book_count": bookCount])
        case let .starterLibrarySeedingFailed(reason):
            return ("starter_library_seed_failed", ["reason": reason])
        }
    }

    private func updateLocalCounters(for event: BMEvent) {
        switch event {
        case .appOpened:
            markDayUsed()
        case .bookAdded:
            incrementCounter(forKey: Keys.booksAdded)
        case .sessionCompleted:
            incrementCounter(forKey: Keys.totalSessionsCompleted)
        case .sessionStarted, .questionAnswered, .starterLibrarySeeded, .starterLibrarySeedingFailed:
            break
        }
    }

    private func incrementCounter(forKey key: String) {
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }

    private func markDayUsed() {
        let today = Self.dayString(from: Date())
        var stored = Set(defaults.stringArray(forKey: Keys.uniqueDays) ?? [])
        let inserted = stored.insert(today).inserted
        if inserted {
            defaults.set(Array(stored), forKey: Keys.uniqueDays)
        }
    }

    private func isFirstSessionCompletion() -> Bool {
        let alreadyCompleted = defaults.bool(forKey: Keys.hasCompletedSessionBefore)
        if alreadyCompleted {
            return false
        } else {
            defaults.set(true, forKey: Keys.hasCompletedSessionBefore)
            return true
        }
    }

    private static func dayString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private enum Keys {
        static let totalSessionsCompleted = "analytics.totalSessionsCompleted"
        static let booksAdded = "analytics.booksAdded"
        static let uniqueDays = "analytics.uniqueDays"
        static let hasCompletedSessionBefore = "analytics.hasCompletedSessionBefore"
    }
}
