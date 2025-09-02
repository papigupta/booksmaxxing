import Foundation
import SwiftData

// MARK: - Mastery Tracking System
// Tracks user progress and mastery for each idea

@Model
final class IdeaMastery {
    var ideaId: String
    var bookId: String
    
    // Core metrics
    var totalQuestionsSeen: Int = 0
    var totalQuestionsCorrect: Int = 0
    var mistakesCount: Int = 0
    var mistakesCorrected: Int = 0
    
    // Question history for mistake tracking
    var missedQuestions: [MissedQuestionRecord] = []
    
    // Mastery calculation
    var currentAccuracy: Double = 0.0
    var masteryPercentage: Double = 0.0
    var isFullyMastered: Bool = false
    
    // FSRS review state
    var reviewStateData: Data?
    
    // Timestamps
    var firstAttemptDate: Date?
    var lastAttemptDate: Date?
    var masteredDate: Date?
    
    init(ideaId: String, bookId: String) {
        self.ideaId = ideaId
        self.bookId = bookId
    }
    
    /// Calculate and update mastery percentage
    func updateMastery() {
        // Base requirement: 8 questions for full mastery
        let baseRequirement = 8
        
        // Calculate effective correct answers (including corrected mistakes)
        let effectiveCorrect = totalQuestionsCorrect + mistakesCorrected
        
        // Calculate mastery percentage
        if totalQuestionsSeen == 0 {
            masteryPercentage = 0.0
            currentAccuracy = 0.0
        } else {
            currentAccuracy = Double(totalQuestionsCorrect) / Double(totalQuestionsSeen) * 100
            
            // Mastery calculation:
            // - Need at least 7/8 correct (87.5%) on first attempt OR
            // - All mistakes must be corrected for 100% mastery
            let baseScore = min(Double(effectiveCorrect) / Double(baseRequirement), 1.0) * 100
            masteryPercentage = baseScore
            
            // Check for full mastery
            isFullyMastered = masteryPercentage >= 100.0 || 
                             (currentAccuracy >= 87.5 && mistakesCount == mistakesCorrected)
            
            if isFullyMastered && masteredDate == nil {
                masteredDate = Date()
            }
        }
    }
    
    /// Record a question attempt
    func recordAttempt(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String) {
        totalQuestionsSeen += 1
        
        if isCorrect {
            totalQuestionsCorrect += 1
            
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
        
        // Recalculate mastery
        updateMastery()
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

// MARK: - Mastery Service
final class MasteryService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get or create mastery record for an idea
    func getMastery(for ideaId: String, bookId: String) -> IdeaMastery {
        let descriptor = FetchDescriptor<IdeaMastery>(
            predicate: #Predicate<IdeaMastery> { mastery in
                mastery.ideaId == ideaId && mastery.bookId == bookId
            }
        )
        
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                print("DEBUG: Found existing mastery for idea \(ideaId): \(existing.masteryPercentage)%")
                return existing
            }
        } catch {
            print("Error fetching mastery: \(error)")
        }
        
        // Create new mastery record
        let newMastery = IdeaMastery(ideaId: ideaId, bookId: bookId)
        modelContext.insert(newMastery)
        
        // Save immediately so it persists
        do {
            try modelContext.save()
            print("DEBUG: Created and saved new mastery for idea \(ideaId)")
        } catch {
            print("ERROR: Failed to save new mastery: \(error)")
        }
        
        return newMastery
    }
    
    /// Update mastery after completing a lesson
    func updateMasteryFromLesson(
        ideaId: String,
        bookId: String,
        responses: [(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String)]
    ) {
        let mastery = getMastery(for: ideaId, bookId: bookId)
        
        for response in responses {
            mastery.recordAttempt(
                questionId: response.questionId,
                isCorrect: response.isCorrect,
                questionText: response.questionText,
                conceptTested: response.conceptTested
            )
        }
        
        // Update FSRS review state if mastered
        if mastery.isFullyMastered {
            let reviewState = FSRSScheduler.initializeReviewState(for: getIdea(ideaId: ideaId))
            mastery.reviewStateData = try? JSONEncoder().encode(reviewState)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving mastery: \(error)")
        }
    }
    
    /// Get ideas that need review based on FSRS
    func getIdeasForReview(bookId: String, limit: Int = 3) -> [String] {
        let descriptor = FetchDescriptor<IdeaMastery>(
            predicate: #Predicate<IdeaMastery> { mastery in
                mastery.bookId == bookId && mastery.isFullyMastered
            }
        )
        
        do {
            let masteredIdeas = try modelContext.fetch(descriptor)
            let needsReview = masteredIdeas.filter { mastery in
                guard let reviewData = mastery.reviewStateData,
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
        let descriptor = FetchDescriptor<IdeaMastery>(
            predicate: #Predicate<IdeaMastery> { mastery in
                mastery.bookId == bookId && mastery.mistakesCount > mastery.mistakesCorrected
            }
        )
        
        do {
            let masteryWithMistakes = try modelContext.fetch(descriptor)
            return masteryWithMistakes.compactMap { mastery in
                let uncorrected = mastery.uncorrectedMistakes
                if !uncorrected.isEmpty {
                    return (mastery.ideaId, Array(uncorrected.prefix(limit)))
                }
                return nil
            }
        } catch {
            print("Error fetching mistakes: \(error)")
            return []
        }
    }
    
    /// Calculate overall book mastery
    func calculateBookMastery(bookId: String, totalIdeas: Int) -> Double {
        let descriptor = FetchDescriptor<IdeaMastery>(
            predicate: #Predicate<IdeaMastery> { mastery in
                mastery.bookId == bookId
            }
        )
        
        do {
            let allMastery = try modelContext.fetch(descriptor)
            let totalMastery = allMastery.reduce(0.0) { $0 + $1.masteryPercentage }
            return totalMastery / Double(totalIdeas)
        } catch {
            print("Error calculating book mastery: \(error)")
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