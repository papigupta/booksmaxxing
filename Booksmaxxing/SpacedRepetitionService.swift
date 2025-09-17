import Foundation
import SwiftData

// MARK: - Spaced Repetition Service

class SpacedRepetitionService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Review Scheduling
    
    func scheduleReviewTest(for idea: Idea, after masteryType: MasteryType) {
        let testProgress = getOrCreateTestProgress(for: idea)
        
        switch masteryType {
        case .fragile:
            // Legacy path deprecated: treat as .none (no scheduling)
            testProgress.nextReviewDate = nil
            idea.masteryLevel = 0
            
        case .solid:
            // No more reviews needed for solid mastery
            testProgress.nextReviewDate = nil
            idea.masteryLevel = 3 // Solid mastery
            
        case .none:
            // No mastery achieved, no review scheduled
            testProgress.nextReviewDate = nil
            idea.masteryLevel = 0
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving review schedule: \(error)")
        }
    }
    
    // MARK: - Review Status

    func isReviewDue(for idea: Idea) -> Bool {
        guard let testProgress = getTestProgress(for: idea),
              let reviewDate = testProgress.nextReviewDate else {
            return false
        }
        
        return reviewDate <= Date()
    }
    
    // MARK: - Helper Methods
    
    private func getOrCreateTestProgress(for idea: Idea) -> TestProgress {
        if let existing = getTestProgress(for: idea) {
            return existing
        }
        
        let newProgress = TestProgress(ideaId: idea.id)
        newProgress.idea = idea
        modelContext.insert(newProgress)
        return newProgress
    }
    
    private func getTestProgress(for idea: Idea) -> TestProgress? {
        let ideaId = idea.id
        let descriptor = FetchDescriptor<TestProgress>(
            predicate: #Predicate<TestProgress> { progress in
                progress.ideaId == ideaId
            }
        )
        
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("Error fetching test progress: \(error)")
            return nil
        }
    }
    
}
