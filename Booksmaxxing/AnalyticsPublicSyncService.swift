import Foundation
import CloudKit
import SwiftData
import CryptoKit

struct AnalyticsPublicRecordPayload: Codable {
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

@MainActor
final class AnalyticsPublicSyncService {
    static let shared = AnalyticsPublicSyncService()

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "CD_UserAnalyticsSnapshot"

    private var modelContext: ModelContext?
    private var isUploading = false
    private var wakeUpTask: Task<Void, Never>?
    private var bufferedPayloads: [AnalyticsPublicRecordPayload] = []

    private init() {
        container = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        database = container.publicCloudDatabase
    }

    func attachModelContext(_ context: ModelContext) {
        modelContext = context
        flushBufferedPayloads()
        Task { await processQueue() }
    }

    func enqueueSync(_ payload: AnalyticsPublicRecordPayload) {
        guard let context = modelContext else {
            bufferedPayloads.append(payload)
            return
        }

        let job = AnalyticsSyncJob(payload: payload)
        context.insert(job)
        do { try context.save() } catch { print("AnalyticsPublicSync enqueue save error: \(error)") }
        Task { await processQueue() }
    }

    private func flushBufferedPayloads() {
        guard !bufferedPayloads.isEmpty else { return }
        let payloads = bufferedPayloads
        bufferedPayloads = []
        for payload in payloads {
            enqueueSync(payload)
        }
    }

    private func processQueue() async {
        guard !isUploading, let context = modelContext else { return }

        var descriptor = FetchDescriptor<AnalyticsSyncJob>(
            sortBy: [SortDescriptor(\.nextAttemptAt, order: .forward), SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        guard let job = try? context.fetch(descriptor).first else { return }

        let now = Date()
        if job.nextAttemptAt > now {
            scheduleWakeUp(at: job.nextAttemptAt)
            return
        }

        isUploading = true
        await upload(job: job)
    }

    private func scheduleWakeUp(at date: Date) {
        wakeUpTask?.cancel()
        let delay = max(date.timeIntervalSinceNow, 0.5)
        wakeUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            await self.processQueue()
        }
    }

    private func upload(job: AnalyticsSyncJob) async {
        defer {
            isUploading = false
        }

        guard let context = modelContext else { return }
        guard let payload = job.payload() else {
            context.delete(job)
            do { try context.save() } catch { print("AnalyticsPublicSync decode error: \(error)") }
            await processQueue()
            return
        }

        let isAccountAvailable = await checkAccountStatus()
        guard isAccountAvailable else {
            reschedule(job: job, message: "iCloud account unavailable", retryable: true)
            await processQueue()
            return
        }

        do {
            try await upsert(payload: payload)
            context.delete(job)
            try context.save()
        } catch {
            handleUploadError(error, for: job)
        }

        await processQueue()
    }

    private func upsert(payload: AnalyticsPublicRecordPayload) async throws {
        let recordID = CKRecord.ID(recordName: sanitizedRecordName(from: payload.recordName))
        let record = try await fetchRecord(with: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        populate(record, from: payload)
        try await saveRecord(record)
    }

    private func fetchRecord(with id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: id) { record, error in
                if let record {
                    continuation.resume(returning: record)
                } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
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

    private func handleUploadError(_ error: Error, for job: AnalyticsSyncJob) {
        if let ckError = error as? CKError {
            if isRetryable(ckError) {
                let message = "CKError retry (\(ckError.code.rawValue)): \(ckError.localizedDescription)"
                reschedule(job: job, message: message, retryable: true)
            } else {
                let message = "CKError fatal (\(ckError.code.rawValue)): \(ckError.localizedDescription)"
                reschedule(job: job, message: message, retryable: false)
            }
        } else {
            reschedule(job: job, message: error.localizedDescription, retryable: true)
        }
    }

    private func reschedule(job: AnalyticsSyncJob, message: String, retryable: Bool) {
        guard let context = modelContext else { return }
        if retryable {
            job.retryCount += 1
            job.lastErrorMessage = message
            let delay = retryDelay(for: job.retryCount)
            job.nextAttemptAt = Date().addingTimeInterval(delay)
            print("AnalyticsPublicSync retrying in \(Int(delay))s: \(message)")
        } else {
            job.lastErrorMessage = message
            print("AnalyticsPublicSync dropping job: \(message)")
            context.delete(job)
        }
        do { try context.save() } catch { print("AnalyticsPublicSync reschedule save error: \(error)") }
    }

    private func retryDelay(for attempt: Int) -> TimeInterval {
        let cappedAttempt = min(attempt, 6)
        return min(pow(2.0, Double(cappedAttempt)) * 5.0, 300.0)
    }

    private func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated, .serverRejectedRequest, .quotaExceeded:
            return true
        default:
            return false
        }
    }

    private func checkAccountStatus() async -> Bool {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    print("AnalyticsPublicSync account status error: \(error)")
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: status == .available)
            }
        }
    }

    private func sanitizedRecordName(from raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "usr_" + digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
