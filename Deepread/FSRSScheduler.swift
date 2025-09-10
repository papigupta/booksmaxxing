import Foundation
import SwiftData

// MARK: - FSRS Algorithm Implementation
// Based on the Free Spaced Repetition Scheduler algorithm
// Optimized for idea mastery rather than traditional flashcard memorization

final class FSRSScheduler {
    
    // MARK: - FSRS Parameters
    private struct FSRSParameters {
        static let initialStability: Double = 1.0  // 1 day for first review
        static let requestRetention: Double = 0.9  // Target 90% retention
        static let maximumInterval: Double = 365.0 // Max 1 year between reviews
        static let easyBonus: Double = 1.3
        static let hardPenalty: Double = 0.6
    }
    
    // MARK: - Review Performance
    enum ReviewPerformance: Int {
        case again = 1  // Failed, needs immediate review
        case hard = 2   // Struggled but correct
        case good = 3   // Normal performance
        case easy = 4   // Perfect, knew it well
        
        var intervalMultiplier: Double {
            switch self {
            case .again: return 0.0  // Reset to day 1
            case .hard: return FSRSParameters.hardPenalty
            case .good: return 1.0
            case .easy: return FSRSParameters.easyBonus
            }
        }
    }
    
    // MARK: - Review State
    struct ReviewState: Codable {
        var stability: Double       // Memory stability (days)
        var difficulty: Double      // Item difficulty (0-1)
        var interval: Double        // Current interval (days)
        var repetitions: Int        // Number of successful reviews
        var lapses: Int            // Number of failures
        var lastReviewDate: Date
        var nextReviewDate: Date
        
        init() {
            self.stability = FSRSParameters.initialStability
            self.difficulty = 0.3  // Default medium difficulty
            self.interval = 1.0
            self.repetitions = 0
            self.lapses = 0
            self.lastReviewDate = Date()
            self.nextReviewDate = Date().addingTimeInterval(86400) // +1 day
        }
    }
    
    // MARK: - Core Scheduling Methods
    
    /// Calculate next review date based on FSRS algorithm
    static func calculateNextReview(
        currentState: ReviewState,
        performance: ReviewPerformance,
        attemptDate: Date = Date()
    ) -> ReviewState {
        var newState = currentState
        newState.lastReviewDate = attemptDate
        
        switch performance {
        case .again:
            // Reset on failure
            newState.interval = 1.0
            newState.stability = FSRSParameters.initialStability
            newState.lapses += 1
            newState.repetitions = 0
            // Increase difficulty
            newState.difficulty = min(1.0, newState.difficulty + 0.2)
            
        case .hard:
            // Reduce interval but don't reset
            newState.interval = max(1.0, currentState.interval * FSRSParameters.hardPenalty)
            newState.stability = currentState.stability * 0.9
            newState.repetitions += 1
            // Slightly increase difficulty
            newState.difficulty = min(1.0, newState.difficulty + 0.1)
            
        case .good:
            // Standard progression
            let successFactor = 1.0 + (Double(newState.repetitions) * 0.1)
            newState.interval = min(
                FSRSParameters.maximumInterval,
                currentState.interval * 2.5 * successFactor
            )
            newState.stability = currentState.stability * 1.2
            newState.repetitions += 1
            // Maintain difficulty
            
        case .easy:
            // Accelerated progression
            let successFactor = 1.0 + (Double(newState.repetitions) * 0.15)
            newState.interval = min(
                FSRSParameters.maximumInterval,
                currentState.interval * 3.0 * successFactor * FSRSParameters.easyBonus
            )
            newState.stability = currentState.stability * 1.5
            newState.repetitions += 1
            // Decrease difficulty
            newState.difficulty = max(0.1, newState.difficulty - 0.1)
        }
        
        // Calculate next review date
        let intervalInSeconds = newState.interval * 86400 // Convert days to seconds
        newState.nextReviewDate = attemptDate.addingTimeInterval(intervalInSeconds)
        
        return newState
    }
    
    /// Determine if an idea needs review
    static func isReviewDue(reviewState: ReviewState, currentDate: Date = Date()) -> Bool {
        return currentDate >= reviewState.nextReviewDate
    }
    
    /// Calculate retention probability (how likely the user remembers)
    static func calculateRetention(
        reviewState: ReviewState,
        currentDate: Date = Date()
    ) -> Double {
        let daysSinceReview = currentDate.timeIntervalSince(reviewState.lastReviewDate) / 86400
        let retentionProbability = exp(-daysSinceReview / reviewState.stability)
        return max(0.0, min(1.0, retentionProbability))
    }
    
    // (Removed getIdeasForReview — coverage/queue flows handle selection)
    
    /// Initialize review state for a newly mastered idea
    static func initializeReviewState(for idea: Idea) -> ReviewState {
        var state = ReviewState()
        
        // Adjust initial parameters based on idea importance
        switch idea.importance {
        case .foundation:
            state.difficulty = 0.2  // Easier, more important
            state.stability = 1.5   // Slightly more stable
        case .buildingBlock:
            state.difficulty = 0.3  // Medium
            state.stability = 1.0
        case .enhancement:
            state.difficulty = 0.4  // Harder, less critical
            state.stability = 0.8
        case .none:
            state.difficulty = 0.3
            state.stability = 1.0
        }
        
        return state
    }
    
    /// Convert performance score to review performance enum
    static func performanceFromScore(correctAnswers: Int, totalQuestions: Int) -> ReviewPerformance {
        let percentage = Double(correctAnswers) / Double(totalQuestions)
        
        switch percentage {
        case 0..<0.6:
            return .again  // Less than 60% - needs immediate review
        case 0.6..<0.75:
            return .hard   // 60-75% - struggled
        case 0.75..<0.95:
            return .good   // 75-95% - normal
        case 0.95...1.0:
            return .easy   // 95-100% - perfect
        default:
            return .good
        }
    }
}

// MARK: - Idea Extension for FSRS
extension Idea {
    /// Stored review state as encoded JSON
    @Transient var reviewState: Data? {
        get { self.reviewStateData }
        set { self.reviewStateData = newValue }
    }
    
    /// Check if this idea needs review
    var needsReview: Bool {
        guard let reviewStateData = reviewState,
              let state = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewStateData) else {
            return false
        }
        return FSRSScheduler.isReviewDue(reviewState: state)
    }
    
    /// Get the retention probability for this idea
    var retentionProbability: Double {
        guard let reviewStateData = reviewState,
              let state = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewStateData) else {
            return 1.0  // Assume perfect retention if not reviewed yet
        }
        return FSRSScheduler.calculateRetention(reviewState: state)
    }
}
