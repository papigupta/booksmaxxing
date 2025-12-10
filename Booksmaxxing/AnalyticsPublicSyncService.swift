import Foundation
import CloudKit

struct AnalyticsPublicRecordPayload {
    let recordName: String
    let userIdentifier: String
    let createdAt: Date
    let lastUpdatedAt: Date
    let firstSeenAt: Date
    let signedInAt: Date?
    let appVersionLastSeen: String?
    let hasEmail: Bool
    let emailStatusRaw: String
    let emailUpdatedAt: Date?
    let hasAddedBook: Bool
    let starterLessonBookCount: Int
    let usedStarterLesson: Bool
    let starterLessonFirstUsedAt: Date?
    let startedLesson: Bool
    let firstLessonStartedAt: Date?
    let finishedLesson: Bool
    let firstLessonFinishedAt: Date?
    let resultsViewed: Bool
    let resultsLastViewedAt: Date?
    let primerOpened: Bool
    let primerFirstOpenedAt: Date?
    let streakPageViewed: Bool
    let streakPageLastViewedAt: Date?
    let activityRingsViewed: Bool
    let activityRingsLastViewedAt: Date?
    let currentStreak: Int
    let bestStreak: Int
    let streakLitToday: Bool
    let brainCaloriesRingClosed: Bool
    let clarityRingClosed: Bool
    let attentionRingClosed: Bool
    let isGuestSession: Bool

    init(snapshot: UserAnalyticsSnapshot, isGuestSession: Bool) {
        self.recordName = snapshot.id
        self.userIdentifier = snapshot.userIdentifier
        self.createdAt = snapshot.createdAt
        self.lastUpdatedAt = snapshot.lastUpdatedAt
        self.firstSeenAt = snapshot.firstSeenAt
        self.signedInAt = snapshot.signedInAt
        self.appVersionLastSeen = snapshot.appVersionLastSeen
        self.hasEmail = snapshot.hasEmail
        self.emailStatusRaw = snapshot.emailStatusRaw
        self.emailUpdatedAt = snapshot.emailUpdatedAt
        self.hasAddedBook = snapshot.hasAddedBook
        self.starterLessonBookCount = snapshot.starterLessonBookCount
        self.usedStarterLesson = snapshot.usedStarterLesson
        self.starterLessonFirstUsedAt = snapshot.starterLessonFirstUsedAt
        self.startedLesson = snapshot.startedLesson
        self.firstLessonStartedAt = snapshot.firstLessonStartedAt
        self.finishedLesson = snapshot.finishedLesson
        self.firstLessonFinishedAt = snapshot.firstLessonFinishedAt
        self.resultsViewed = snapshot.resultsViewed
        self.resultsLastViewedAt = snapshot.resultsLastViewedAt
        self.primerOpened = snapshot.primerOpened
        self.primerFirstOpenedAt = snapshot.primerFirstOpenedAt
        self.streakPageViewed = snapshot.streakPageViewed
        self.streakPageLastViewedAt = snapshot.streakPageLastViewedAt
        self.activityRingsViewed = snapshot.activityRingsViewed
        self.activityRingsLastViewedAt = snapshot.activityRingsLastViewedAt
        self.currentStreak = snapshot.currentStreak
        self.bestStreak = snapshot.bestStreak
        self.streakLitToday = snapshot.streakLitToday
        self.brainCaloriesRingClosed = snapshot.brainCaloriesRingClosed
        self.clarityRingClosed = snapshot.clarityRingClosed
        self.attentionRingClosed = snapshot.attentionRingClosed
        self.isGuestSession = isGuestSession
    }
}

final class AnalyticsPublicSyncService {
    static let shared = AnalyticsPublicSyncService()

    private let database: CKDatabase
    private let queue = DispatchQueue(label: "AnalyticsPublicSyncServiceQueue")
    private let recordType = "CD_UserAnalyticsSnapshot"

    private init() {
        database = CKContainer(identifier: CloudKitConfig.containerIdentifier).publicCloudDatabase
    }

    func enqueueSync(_ payload: AnalyticsPublicRecordPayload) {
        queue.async { [weak self] in
            self?.upsert(payload: payload)
        }
    }

    private func upsert(payload: AnalyticsPublicRecordPayload) {
        let recordID = CKRecord.ID(recordName: payload.recordName)
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self else { return }

            let recordToSave: CKRecord
            if let record {
                recordToSave = record
            } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                recordToSave = CKRecord(recordType: self.recordType, recordID: recordID)
            } else if let error {
                print("AnalyticsPublicSync fetch error: \(error)")
                return
            } else {
                recordToSave = CKRecord(recordType: self.recordType, recordID: recordID)
            }

            self.populate(recordToSave, from: payload)
            self.database.save(recordToSave) { _, error in
                if let error {
                    print("AnalyticsPublicSync save error: \(error)")
                }
            }
        }
    }

    private func populate(_ record: CKRecord, from payload: AnalyticsPublicRecordPayload) {
        record["userIdentifier"] = payload.userIdentifier as NSString
        record["createdAt"] = payload.createdAt as NSDate
        record["lastUpdatedAt"] = payload.lastUpdatedAt as NSDate
        record["firstSeenAt"] = payload.firstSeenAt as NSDate
        record["signedInAt"] = payload.signedInAt as NSDate?
        record["appVersionLastSeen"] = payload.appVersionLastSeen as NSString?
        record["hasEmail"] = NSNumber(value: payload.hasEmail)
        record["emailStatusRaw"] = payload.emailStatusRaw as NSString
        record["emailUpdatedAt"] = payload.emailUpdatedAt as NSDate?
        record["hasAddedBook"] = NSNumber(value: payload.hasAddedBook)
        record["starterLessonBookCount"] = NSNumber(value: payload.starterLessonBookCount)
        record["usedStarterLesson"] = NSNumber(value: payload.usedStarterLesson)
        record["starterLessonFirstUsedAt"] = payload.starterLessonFirstUsedAt as NSDate?
        record["startedLesson"] = NSNumber(value: payload.startedLesson)
        record["firstLessonStartedAt"] = payload.firstLessonStartedAt as NSDate?
        record["finishedLesson"] = NSNumber(value: payload.finishedLesson)
        record["firstLessonFinishedAt"] = payload.firstLessonFinishedAt as NSDate?
        record["resultsViewed"] = NSNumber(value: payload.resultsViewed)
        record["resultsLastViewedAt"] = payload.resultsLastViewedAt as NSDate?
        record["primerOpened"] = NSNumber(value: payload.primerOpened)
        record["primerFirstOpenedAt"] = payload.primerFirstOpenedAt as NSDate?
        record["streakPageViewed"] = NSNumber(value: payload.streakPageViewed)
        record["streakPageLastViewedAt"] = payload.streakPageLastViewedAt as NSDate?
        record["activityRingsViewed"] = NSNumber(value: payload.activityRingsViewed)
        record["activityRingsLastViewedAt"] = payload.activityRingsLastViewedAt as NSDate?
        record["currentStreak"] = NSNumber(value: payload.currentStreak)
        record["bestStreak"] = NSNumber(value: payload.bestStreak)
        record["streakLitToday"] = NSNumber(value: payload.streakLitToday)
        record["brainCaloriesRingClosed"] = NSNumber(value: payload.brainCaloriesRingClosed)
        record["clarityRingClosed"] = NSNumber(value: payload.clarityRingClosed)
        record["attentionRingClosed"] = NSNumber(value: payload.attentionRingClosed)
        record["isGuestSession"] = NSNumber(value: payload.isGuestSession)
    }
}
