import Foundation
import SwiftData

// MARK: - Legacy Model (for migration)
// This represents the old IdeaMastery model structure
@Model
final class IdeaMastery {
    var ideaId: String = ""
    var bookId: String = ""
    var totalQuestionsSeen: Int = 0
    var totalQuestionsCorrect: Int = 0
    var mistakesCount: Int = 0
    var mistakesCorrected: Int = 0
    var missedQuestions: [MissedQuestionRecord]?
    var currentAccuracy: Double = 0.0
    var masteryPercentage: Double = 0.0
    var isFullyMastered: Bool = false
    var reviewStateData: Data?
    var firstAttemptDate: Date?
    var lastAttemptDate: Date?
    var masteredDate: Date?
    
    init(ideaId: String, bookId: String) {
        self.ideaId = ideaId
        self.bookId = bookId
    }
}

// MARK: - Migration Service
final class CoverageMigrationService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Migrate old IdeaMastery records to new IdeaCoverage format
    func migrateOldMasteryToCoverage() {
        print("DEBUG: Starting migration from IdeaMastery to IdeaCoverage")
        
        // Fetch all old mastery records
        let descriptor = FetchDescriptor<IdeaMastery>()
        
        do {
            let oldMasteryRecords = try modelContext.fetch(descriptor)
            print("DEBUG: Found \(oldMasteryRecords.count) old mastery records to migrate")
            
            var migratedCount = 0
            
            for oldRecord in oldMasteryRecords {
                // Check if coverage already exists for this idea
                let ideaId = oldRecord.ideaId
                let bookId = oldRecord.bookId
                
                let coverageDescriptor = FetchDescriptor<IdeaCoverage>(
                    predicate: #Predicate<IdeaCoverage> { coverage in
                        coverage.ideaId == ideaId && coverage.bookId == bookId
                    }
                )
                
                let existingCoverage = try modelContext.fetch(coverageDescriptor).first
                
                if existingCoverage == nil {
                    // Create new coverage record from old mastery
                    let newCoverage = IdeaCoverage(ideaId: oldRecord.ideaId, bookId: oldRecord.bookId)
                    
                    // Copy over the data
                    newCoverage.totalQuestionsSeen = oldRecord.totalQuestionsSeen
                    newCoverage.totalQuestionsCorrect = oldRecord.totalQuestionsCorrect
                    newCoverage.mistakesCount = oldRecord.mistakesCount
                    newCoverage.mistakesCorrected = oldRecord.mistakesCorrected
                    newCoverage.missedQuestions = oldRecord.missedQuestions
                    newCoverage.currentAccuracy = oldRecord.currentAccuracy
                    newCoverage.coveragePercentage = oldRecord.masteryPercentage
                    newCoverage.isFullyCovered = oldRecord.isFullyMastered
                    newCoverage.reviewStateData = oldRecord.reviewStateData
                    newCoverage.firstAttemptDate = oldRecord.firstAttemptDate
                    newCoverage.lastAttemptDate = oldRecord.lastAttemptDate
                    newCoverage.coveredDate = oldRecord.masteredDate
                    
                    // Note: coveredCategories will be empty for migrated data
                    // Users will need to re-answer questions to properly track BloomCategories
                    newCoverage.coveredCategories = []
                    
                    modelContext.insert(newCoverage)
                    migratedCount += 1
                    print("DEBUG: Migrated mastery for idea \(oldRecord.ideaId)")
                }
                
                // Delete the old mastery record
                modelContext.delete(oldRecord)
            }
            
            // Save all changes
            try modelContext.save()
            print("DEBUG: Successfully migrated \(migratedCount) records from IdeaMastery to IdeaCoverage")
            
        } catch {
            print("DEBUG: Error during migration: \(error)")
            print("DEBUG: This might be normal if no old data exists")
        }
    }
    
    /// Clear all old mastery records (use with caution)
    func clearOldMasteryData() {
        let descriptor = FetchDescriptor<IdeaMastery>()
        
        do {
            let oldRecords = try modelContext.fetch(descriptor)
            print("DEBUG: Clearing \(oldRecords.count) old mastery records")
            
            for record in oldRecords {
                modelContext.delete(record)
            }
            
            try modelContext.save()
            print("DEBUG: Successfully cleared old mastery data")
        } catch {
            print("DEBUG: Error clearing old mastery data: \(error)")
        }
    }
}
