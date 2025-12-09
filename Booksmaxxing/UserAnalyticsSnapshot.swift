import Foundation
import SwiftData

@Model
final class UserAnalyticsSnapshot {
    var id: String = ""
    var userIdentifier: String = ""

    var createdAt: Date = Date()
    var lastUpdatedAt: Date = Date()
    var firstSeenAt: Date = Date()
    var signedInAt: Date?
    var appVersionLastSeen: String?

    var hasEmail: Bool = false
    var emailStatusRaw: String = EmailStatus.unknown.rawValue
    var emailUpdatedAt: Date?

    var hasAddedBook: Bool = false
    var starterLessonBookCount: Int = 0
    var usedStarterLesson: Bool = false
    var starterLessonFirstUsedAt: Date?

    var startedLesson: Bool = false
    var firstLessonStartedAt: Date?
    var finishedLesson: Bool = false
    var firstLessonFinishedAt: Date?

    var resultsViewed: Bool = false
    var resultsLastViewedAt: Date?

    var primerOpened: Bool = false
    var primerFirstOpenedAt: Date?

    var streakPageViewed: Bool = false
    var streakPageLastViewedAt: Date?

    var activityRingsViewed: Bool = false
    var activityRingsLastViewedAt: Date?

    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var streakLitToday: Bool = false

    var brainCaloriesRingClosed: Bool = false
    var clarityRingClosed: Bool = false
    var attentionRingClosed: Bool = false

    init(id: String, userIdentifier: String, firstSeenAt: Date = Date()) {
        self.id = id
        self.userIdentifier = userIdentifier
        self.firstSeenAt = firstSeenAt
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
    }

    var emailStatus: EmailStatus {
        get { EmailStatus(rawValue: emailStatusRaw) ?? .unknown }
        set { emailStatusRaw = newValue.rawValue }
    }
}
