import Foundation
import SwiftData

// MARK: - Fragile Mastery Cleanup Migration
// Converts any legacy 'fragile' mastery records to 'none' and clears fragile review dates.

final class FragileMasteryMigrationService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func cleanupFragileMastery() {
        var updatedAttempts = 0
        var updatedProgress = 0

        // Update TestAttempt.masteryAchieved from .fragile -> .none
        do {
            let attemptsDescriptor = FetchDescriptor<TestAttempt>()
            let attempts = try modelContext.fetch(attemptsDescriptor)
            for attempt in attempts where attempt.masteryAchieved == .fragile {
                attempt.masteryAchieved = .none
                updatedAttempts += 1
            }
        } catch {
            print("⚠️ FragileMasteryMigration: failed to fetch TestAttempt records: \(error)")
        }

        // Update TestProgress.masteryType from .fragile -> .none and clear nextReviewDate
        do {
            let progressDescriptor = FetchDescriptor<TestProgress>()
            let progressItems = try modelContext.fetch(progressDescriptor)
            for progress in progressItems where progress.masteryType == .fragile {
                progress.masteryType = .none
                progress.nextReviewDate = nil
                updatedProgress += 1
            }
        } catch {
            print("⚠️ FragileMasteryMigration: failed to fetch TestProgress records: \(error)")
        }

        do {
            if updatedAttempts > 0 || updatedProgress > 0 {
                try modelContext.save()
                print("✅ FragileMasteryMigration: updated attempts=\(updatedAttempts), progress=\(updatedProgress)")
            } else {
                print("ℹ️ FragileMasteryMigration: no fragile records found")
            }
        } catch {
            print("❌ FragileMasteryMigration: failed to save updates: \(error)")
        }
    }
}
