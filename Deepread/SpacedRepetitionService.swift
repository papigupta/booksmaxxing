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
            // Schedule review in 3 days for fragile mastery
            testProgress.nextReviewDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
            idea.masteryLevel = 1 // Fragile mastery
            
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
    
    func getIdeasNeedingReview() -> [Idea] {
        let now = Date()
        let descriptor = FetchDescriptor<TestProgress>()
        // Remove the problematic predicate and filter in code instead
        
        do {
            let progressItems = try modelContext.fetch(descriptor)
            
            // Filter in code to avoid SwiftData predicate issues
            let dueItems = progressItems.filter { progress in
                guard let reviewDate = progress.nextReviewDate else { return false }
                return reviewDate <= now
            }
            
            let ideaIds = dueItems.map { $0.ideaId }
            
            // Use a simpler approach to avoid predicate issues
            let allIdeasDescriptor = FetchDescriptor<Idea>()
            let allIdeas = try modelContext.fetch(allIdeasDescriptor)
            return allIdeas.filter { ideaIds.contains($0.id) }
        } catch {
            print("Error fetching ideas needing review: \(error)")
            return []
        }
    }
    
    func isReviewDue(for idea: Idea) -> Bool {
        guard let testProgress = getTestProgress(for: idea),
              let reviewDate = testProgress.nextReviewDate else {
            return false
        }
        
        return reviewDate <= Date()
    }
    
    func daysUntilReview(for idea: Idea) -> Int? {
        guard let testProgress = getTestProgress(for: idea),
              let reviewDate = testProgress.nextReviewDate else {
            return nil
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: reviewDate)
        return components.day
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
    
    // MARK: - Review Statistics
    
    func getReviewStatistics() -> ReviewStatistics {
        let now = Date()
        
        // Get all test progress items
        let descriptor = FetchDescriptor<TestProgress>()
        
        do {
            let allProgress = try modelContext.fetch(descriptor)
            
            let dueToday = allProgress.filter { progress in
                guard let reviewDate = progress.nextReviewDate else { return false }
                return Calendar.current.isDate(reviewDate, inSameDayAs: now)
            }.count
            
            let overdue = allProgress.filter { progress in
                guard let reviewDate = progress.nextReviewDate else { return false }
                return reviewDate < Calendar.current.startOfDay(for: now)
            }.count
            
            let upcoming = allProgress.filter { progress in
                guard let reviewDate = progress.nextReviewDate else { return false }
                return reviewDate > now
            }.count
            
            let solidMastery = allProgress.filter { $0.masteryType == .solid }.count
            let fragileMastery = allProgress.filter { $0.masteryType == .fragile }.count
            
            return ReviewStatistics(
                dueToday: dueToday,
                overdue: overdue,
                upcoming: upcoming,
                solidMastery: solidMastery,
                fragileMastery: fragileMastery
            )
        } catch {
            print("Error fetching review statistics: \(error)")
            return ReviewStatistics(dueToday: 0, overdue: 0, upcoming: 0, solidMastery: 0, fragileMastery: 0)
        }
    }
}

// MARK: - Review Statistics Model

struct ReviewStatistics {
    let dueToday: Int
    let overdue: Int
    let upcoming: Int
    let solidMastery: Int
    let fragileMastery: Int
    
    var totalDue: Int {
        dueToday + overdue
    }
}