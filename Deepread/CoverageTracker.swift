import Foundation
import SwiftData

// MARK: - Coverage Tracking System
// Tracks user progress and coverage for each idea

@Model
final class IdeaCoverage {
    var ideaId: String
    var bookId: String
    
    // Core metrics
    var totalQuestionsSeen: Int = 0
    var totalQuestionsCorrect: Int = 0
    var mistakesCount: Int = 0
    var mistakesCorrected: Int = 0
    
    // Track which BloomCategory questions have been answered correctly  
    @Attribute(.transformable) var coveredCategories: [String] = [] // Stores BloomCategory raw values that have been answered correctly
    
    // Question history for mistake tracking
    @Relationship(deleteRule: .cascade) var missedQuestions: [MissedQuestionRecord] = []
    
    // Coverage calculation (not mastery - just whether questions have been answered)
    var currentAccuracy: Double = 0.0
    var coveragePercentage: Double = 0.0
    var isFullyCovered: Bool = false
    
    // FSRS review state
    var reviewStateData: Data?
    
    // Timestamps
    var firstAttemptDate: Date?
    var lastAttemptDate: Date?
    var coveredDate: Date? // Date when all 8 question types were covered
    
    init(ideaId: String, bookId: String) {
        self.ideaId = ideaId
        self.bookId = bookId
    }
    
    /// Calculate and update coverage percentage
    func updateCoverage() {
        // Coverage is based on 8 BloomCategory types
        // Each correctly answered type = 12.5% coverage
        let totalCategories = 8
        let uniqueCategoriesCovered = Set(coveredCategories).count
        
        // Calculate coverage percentage
        coveragePercentage = (Double(uniqueCategoriesCovered) / Double(totalCategories)) * 100.0
        
        // Calculate accuracy for stats (but not used for coverage)
        if totalQuestionsSeen > 0 {
            currentAccuracy = Double(totalQuestionsCorrect) / Double(totalQuestionsSeen) * 100
        } else {
            currentAccuracy = 0.0
        }
        
        // Check for full coverage (all 8 types answered correctly at least once)
        isFullyCovered = uniqueCategoriesCovered >= totalCategories
        
        if isFullyCovered && coveredDate == nil {
            coveredDate = Date()
        }
    }
    
    /// Record a question attempt with BloomCategory tracking
    func recordAttempt(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String, bloomCategory: String) {
        print("DEBUG: Recording attempt for idea \(ideaId), bloomCategory: \(bloomCategory), isCorrect: \(isCorrect)")
        totalQuestionsSeen += 1
        
        if isCorrect {
            totalQuestionsCorrect += 1
            
            // Track this BloomCategory as covered
            if !coveredCategories.contains(bloomCategory) {
                coveredCategories.append(bloomCategory)
                print("DEBUG: Added new bloom category \(bloomCategory) to covered categories. Total covered: \(coveredCategories.count)")
            } else {
                print("DEBUG: Bloom category \(bloomCategory) already covered")
            }
            
            // Check if this was a correction of a previous mistake
            if let missedIndex = missedQuestions.firstIndex(where: { $0.originalQuestionId == questionId || $0.conceptTested == conceptTested }) {
                if !missedQuestions[missedIndex].isCorrected {
                    missedQuestions[missedIndex].isCorrected = true
                    missedQuestions[missedIndex].correctedDate = Date()
                    mistakesCorrected += 1
                }
            }
        } else {
            mistakesCount += 1
            
            // Record the missed question if not already recorded
            if !missedQuestions.contains(where: { $0.conceptTested == conceptTested }) {
                let missedRecord = MissedQuestionRecord(
                    originalQuestionId: questionId,
                    questionText: questionText,
                    conceptTested: conceptTested,
                    attemptDate: Date()
                )
                missedQuestions.append(missedRecord)
            }
        }
        
        // Update timestamps
        if firstAttemptDate == nil {
            firstAttemptDate = Date()
        }
        lastAttemptDate = Date()
        
        // Recalculate coverage
        updateCoverage()
        print("DEBUG: After update - Coverage: \(coveragePercentage)%, Categories covered: \(Set(coveredCategories).count)/8")
        print("DEBUG: Covered categories: \(coveredCategories)")
    }
    
    /// Get uncorrected mistakes for review
    var uncorrectedMistakes: [MissedQuestionRecord] {
        missedQuestions.filter { !$0.isCorrected }
    }
}

// MARK: - Missed Question Record
@Model
final class MissedQuestionRecord {
    var originalQuestionId: String
    var questionText: String
    var conceptTested: String
    var attemptDate: Date
    var isCorrected: Bool = false
    var correctedDate: Date?
    
    init(originalQuestionId: String, questionText: String, conceptTested: String, attemptDate: Date) {
        self.originalQuestionId = originalQuestionId
        self.questionText = questionText
        self.conceptTested = conceptTested
        self.attemptDate = attemptDate
    }
}

// MARK: - Coverage Service
final class CoverageService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get or create coverage record for an idea
    func getCoverage(for ideaId: String, bookId: String) -> IdeaCoverage {
        print("DEBUG: getCoverage called for ideaId: '\(ideaId)', bookId: '\(bookId)'")
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { coverage in
                coverage.ideaId == ideaId && coverage.bookId == bookId
            }
        )
        
        do {
            let allCoverage = try modelContext.fetch(descriptor)
            print("DEBUG: Found \(allCoverage.count) coverage records for ideaId: \(ideaId)")
            
            if let existing = allCoverage.first {
                print("DEBUG: Found existing coverage for idea \(ideaId): \(existing.coveragePercentage)%, categories: \(existing.coveredCategories.count)")
                return existing
            }
        } catch {
            print("Error fetching coverage: \(error)")
        }
        
        // Create new coverage record
        print("DEBUG: Creating NEW coverage record for ideaId: \(ideaId), bookId: \(bookId)")
        let newCoverage = IdeaCoverage(ideaId: ideaId, bookId: bookId)
        modelContext.insert(newCoverage)
        
        // Save immediately so it persists
        do {
            try modelContext.save()
            print("DEBUG: Created and saved new coverage for idea \(ideaId)")
        } catch {
            print("ERROR: Failed to save new coverage: \(error)")
        }
        
        return newCoverage
    }
    
    /// Update coverage after completing a lesson
    func updateCoverageFromLesson(
        ideaId: String,
        bookId: String,
        responses: [(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String, bloomCategory: String)]
    ) {
        print("DEBUG: updateCoverageFromLesson called for idea \(ideaId) with \(responses.count) responses")
        let coverage = getCoverage(for: ideaId, bookId: bookId)
        
        for response in responses {
            print("DEBUG: Calling recordAttempt for bloom: \(response.bloomCategory), correct: \(response.isCorrect)")
            coverage.recordAttempt(
                questionId: response.questionId,
                isCorrect: response.isCorrect,
                questionText: response.questionText,
                conceptTested: response.conceptTested,
                bloomCategory: response.bloomCategory
            )
        }
        
        // Update FSRS review state if fully covered
        if coverage.isFullyCovered {
            let reviewState = FSRSScheduler.initializeReviewState(for: getIdea(ideaId: ideaId))
            coverage.reviewStateData = try? JSONEncoder().encode(reviewState)
        }
        
        do {
            try modelContext.save()
            print("DEBUG: Successfully saved coverage for idea \(ideaId). Coverage: \(coverage.coveragePercentage)%")
        } catch {
            print("ERROR: Failed to save coverage for idea \(ideaId): \(error)")
        }
    }
    
    /// Get ideas that need review based on FSRS
    func getIdeasForReview(bookId: String, limit: Int = 3) -> [String] {
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { coverage in
                coverage.bookId == bookId && coverage.isFullyCovered
            }
        )
        
        do {
            let coveredIdeas = try modelContext.fetch(descriptor)
            let needsReview = coveredIdeas.filter { coverage in
                guard let reviewData = coverage.reviewStateData,
                      let reviewState = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewData) else {
                    return false
                }
                return FSRSScheduler.isReviewDue(reviewState: reviewState)
            }.sorted { m1, m2 in
                // Sort by urgency
                guard let r1 = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: m1.reviewStateData!),
                      let r2 = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: m2.reviewStateData!) else {
                    return false
                }
                return r1.nextReviewDate < r2.nextReviewDate
            }
            
            return Array(needsReview.prefix(limit)).map { $0.ideaId }
        } catch {
            print("Error fetching ideas for review: \(error)")
            return []
        }
    }
    
    /// Get mistakes that need correction
    func getMistakesForCorrection(bookId: String, limit: Int = 2) -> [(ideaId: String, mistakes: [MissedQuestionRecord])] {
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { coverage in
                coverage.bookId == bookId && coverage.mistakesCount > coverage.mistakesCorrected
            }
        )
        
        do {
            let coverageWithMistakes = try modelContext.fetch(descriptor)
            return coverageWithMistakes.compactMap { coverage in
                let uncorrected = coverage.uncorrectedMistakes
                if !uncorrected.isEmpty {
                    return (coverage.ideaId, Array(uncorrected.prefix(limit)))
                }
                return nil
            }
        } catch {
            print("Error fetching mistakes: \(error)")
            return []
        }
    }
    
    /// Calculate overall book coverage
    func calculateBookCoverage(bookId: String, totalIdeas: Int) -> Double {
        print("DEBUG: Calculating book coverage for bookId: '\(bookId)', totalIdeas: \(totalIdeas)")
        
        // Debug: List all coverage records
        let allDescriptor = FetchDescriptor<IdeaCoverage>()
        if let allCoverage = try? modelContext.fetch(allDescriptor) {
            print("DEBUG: All coverage records in database:")
            for cov in allCoverage {
                print("  - ideaId: '\(cov.ideaId)', bookId: '\(cov.bookId)', coverage: \(cov.coveragePercentage)%, categories: \(cov.coveredCategories)")
            }
        }
        
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { coverage in
                coverage.bookId == bookId
            }
        )
        
        do {
            let allCoverage = try modelContext.fetch(descriptor)
            // Book coverage = (number of fully covered ideas / total ideas) * 100
            let fullyCoveredCount = allCoverage.filter { $0.isFullyCovered }.count
            return (Double(fullyCoveredCount) / Double(totalIdeas)) * 100.0
        } catch {
            print("Error calculating book coverage: \(error)")
            return 0.0
        }
    }
    
    // Helper to get idea (would be implemented based on your data model)
    private func getIdea(ideaId: String) -> Idea {
        // This would fetch the actual idea from the database
        // Placeholder for now
        return Idea(
            id: ideaId,
            title: "",
            description: "",
            bookTitle: "",
            depthTarget: 3
        )
    }
}