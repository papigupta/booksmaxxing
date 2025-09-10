import Foundation
import SwiftData
import OSLog

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
    var coveredCategories: [String] = [] // Stores BloomCategory raw values that have been answered correctly
    
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
    
    // Curveball mastery gate
    var curveballDueDate: Date?
    var curveballPassed: Bool = false
    var curveballPassedAt: Date?
    
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
            // Schedule curveball if not already scheduled or passed
            if !curveballPassed && curveballDueDate == nil {
                // Default: 3 days; can be adjusted via config elsewhere
                let days = CurveballConfig.delayDays
                curveballDueDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
        }
    }
    
    /// Record a question attempt with BloomCategory tracking
    func recordAttempt(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String, bloomCategory: String) {
        print("🔍 DEBUG: Recording attempt for idea \(ideaId)")
        print("   - BloomCategory: \(bloomCategory)")
        print("   - isCorrect: \(isCorrect)")
        print("   - Question ID: \(questionId)")
        print("   - Current covered categories: \(coveredCategories)")
        print("   - Current coverage %: \(coveragePercentage)")
        
        totalQuestionsSeen += 1
        
        if isCorrect {
            totalQuestionsCorrect += 1
            
            // Track this BloomCategory as covered
            if !coveredCategories.contains(bloomCategory) {
                coveredCategories.append(bloomCategory)
                print("✅ DEBUG: Added NEW bloom category \(bloomCategory)")
                print("   - Total unique categories covered: \(Set(coveredCategories).count)/8")
                print("   - All covered categories: \(Set(coveredCategories).sorted())")
            } else {
                print("⚠️ DEBUG: Bloom category \(bloomCategory) already covered")
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
            
            // Record the missed question if not already recorded, else increment retry count
            if let idx = missedQuestions.firstIndex(where: { $0.conceptTested == conceptTested }) {
                missedQuestions[idx].retryCount += 1
            } else {
                let missedRecord = MissedQuestionRecord(
                    originalQuestionId: questionId,
                    questionText: questionText,
                    conceptTested: conceptTested,
                    attemptDate: Date()
                )
                missedRecord.retryCount = 1
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
        print("📊 DEBUG: After update:")
        print("   - Coverage: \(coveragePercentage)%")
        print("   - Unique categories covered: \(Set(coveredCategories).count)/8")
        print("   - All categories (with duplicates): \(coveredCategories)")
        print("   - Unique categories: \(Set(coveredCategories).sorted())")
        print("   - Total questions seen: \(totalQuestionsSeen)")
        print("   - Total correct: \(totalQuestionsCorrect)")
        print("   - Accuracy: \(currentAccuracy)%")
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
    var retryCount: Int = 0
    
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
    private let logger = Logger(subsystem: "com.deepread.app", category: "Coverage")
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get or create coverage record for an idea
    func getCoverage(for ideaId: String, bookId: String) -> IdeaCoverage {
        logger.debug("getCoverage(ideaId=\(ideaId, privacy: .public), bookId=\(bookId, privacy: .public))")
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { coverage in
                coverage.ideaId == ideaId && coverage.bookId == bookId
            }
        )
        
        do {
            let allCoverage = try modelContext.fetch(descriptor)
            logger.debug("Found \(allCoverage.count) coverage records for ideaId: \(ideaId, privacy: .public)")
            
            if let existing = allCoverage.first {
                logger.debug("Found existing coverage for idea \(ideaId, privacy: .public): \(existing.coveragePercentage, privacy: .public)% categories: \(existing.coveredCategories.count)")
                return existing
            }
        } catch {
            logger.error("Error fetching coverage: \(String(describing: error))")
        }
        
        // Create new coverage record
        logger.debug("Creating NEW coverage record for ideaId: \(ideaId, privacy: .public), bookId: \(bookId, privacy: .public)")
        let newCoverage = IdeaCoverage(ideaId: ideaId, bookId: bookId)
        modelContext.insert(newCoverage)
        
        // Save immediately so it persists
        do {
            try modelContext.save()
            logger.debug("Created and saved new coverage for idea \(ideaId, privacy: .public)")
        } catch {
            logger.error("Failed to save new coverage: \(String(describing: error))")
        }
        
        return newCoverage
    }
    
    /// Update coverage after completing a lesson
    func updateCoverageFromLesson(
        ideaId: String,
        bookId: String,
        responses: [(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String, bloomCategory: String)]
    ) {
        logger.debug("updateCoverageFromLesson: ideaId=\(ideaId, privacy: .public), bookId=\(bookId, privacy: .public), responses=\(responses.count)")
        
        // Show all bloom categories being processed
        _ = responses.map { $0.bloomCategory }
        
        let coverage = getCoverage(for: ideaId, bookId: bookId)
        logger.debug("Current coverage before: \(coverage.coveragePercentage, privacy: .public)% covered=\(coverage.coveredCategories.count)")
        
        for (index, response) in responses.enumerated() {
            logger.debug("Processing response \(index + 1)/\(responses.count)")
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
            logger.debug("Saved coverage for idea \(ideaId, privacy: .public). Coverage: \(coverage.coveragePercentage, privacy: .public)%")
        } catch {
            logger.error("Failed to save coverage for idea \(ideaId, privacy: .public): \(String(describing: error))")
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
            logger.error("Error fetching ideas for review: \(String(describing: error))")
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
            logger.error("Error fetching mistakes: \(String(describing: error))")
            return []
        }
    }
    
    /// Calculate overall book coverage
    func calculateBookCoverage(bookId: String, totalIdeas: Int) -> Double {
        logger.debug("Calculating book coverage for bookId=\(bookId, privacy: .public), totalIdeas=\(totalIdeas)")
        
        // Debug: List all coverage records
        let allDescriptor = FetchDescriptor<IdeaCoverage>()
        _ = try? modelContext.fetch(allDescriptor)
        
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
            logger.error("Error calculating book coverage: \(String(describing: error))")
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
