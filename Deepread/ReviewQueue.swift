import Foundation
import SwiftData

// MARK: - Review Queue Models

@Model
final class ReviewQueueItem {
    var id: UUID
    var ideaId: String
    var ideaTitle: String
    var bookTitle: String
    var questionType: QuestionType
    var conceptTested: String
    var difficulty: QuestionDifficulty
    var bloomCategory: BloomCategory
    var originalQuestionText: String
    var addedDate: Date
    var isCompleted: Bool
    
    init(
        ideaId: String,
        ideaTitle: String,
        bookTitle: String,
        questionType: QuestionType,
        conceptTested: String,
        difficulty: QuestionDifficulty,
        bloomCategory: BloomCategory,
        originalQuestionText: String
    ) {
        self.id = UUID()
        self.ideaId = ideaId
        self.ideaTitle = ideaTitle
        self.bookTitle = bookTitle
        self.questionType = questionType
        self.conceptTested = conceptTested
        self.difficulty = difficulty
        self.bloomCategory = bloomCategory
        self.originalQuestionText = originalQuestionText
        self.addedDate = Date()
        self.isCompleted = false
    }
}

// MARK: - Review Queue Manager

class ReviewQueueManager {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Add Mistakes to Queue
    
    func addMistakesToQueue(from attempt: TestAttempt, test: Test, idea: Idea) {
        let incorrectResponses = attempt.responses.filter { !$0.isCorrect }
        
        for response in incorrectResponses {
            // Find the original question
            guard let question = test.questions.first(where: { $0.id == response.questionId }) else {
                continue
            }
            
            // Create a review queue item for this mistake
            let queueItem = ReviewQueueItem(
                ideaId: idea.id,
                ideaTitle: idea.title,
                bookTitle: idea.bookTitle,
                questionType: question.type,
                conceptTested: "\(question.bloomCategory.rawValue)-\(question.difficulty.rawValue)",
                difficulty: question.difficulty,
                bloomCategory: question.bloomCategory,
                originalQuestionText: question.questionText
            )
            
            modelContext.insert(queueItem)
        }
        
        do {
            try modelContext.save()
            print("🔄 REVIEW QUEUE: Added \(incorrectResponses.count) mistakes to review queue for idea '\(idea.title)'")
        } catch {
            print("❌ Error saving review queue items: \(error)")
        }
    }
    
    // MARK: - Get Daily Review Questions
    
    func getDailyReviewItems(for bookTitle: String) -> (mcqs: [ReviewQueueItem], openEnded: [ReviewQueueItem]) {
        let targetBookTitle = bookTitle
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                !item.isCompleted && item.bookTitle == targetBookTitle
            },
            sortBy: [SortDescriptor(\.addedDate)]
        )
        
        do {
            let allPendingItems = try modelContext.fetch(descriptor)
            
            // Separate MCQs and Open-Ended questions
            let mcqItems = allPendingItems.filter { $0.questionType == .mcq }
            let openEndedItems = allPendingItems.filter { $0.questionType == .openEnded }
            
            // Apply daily limits: up to 3 MCQs and max 1 OEQ (total max 4)
            let selectedMCQs = Array(mcqItems.prefix(3))  // Max 3 MCQs
            let selectedOpenEnded = Array(openEndedItems.prefix(1))  // Max 1 OEQ
            
            return (mcqs: selectedMCQs, openEnded: selectedOpenEnded)
        } catch {
            print("Error fetching review queue items: \(error)")
            return (mcqs: [], openEnded: [])
        }
    }
    
    // MARK: - Get Queue Statistics
    
    func getQueueStatistics(for bookTitle: String) -> (totalMCQs: Int, totalOpenEnded: Int) {
        print("🔍 REVIEW QUEUE: getQueueStatistics() called for book: \(bookTitle)")
        let targetBookTitle = bookTitle
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                !item.isCompleted && item.bookTitle == targetBookTitle
            }
        )
        
        do {
            let allPendingItems = try modelContext.fetch(descriptor)
            let mcqCount = allPendingItems.filter { $0.questionType == .mcq }.count
            let openEndedCount = allPendingItems.filter { $0.questionType == .openEnded }.count
            
            print("🔄 REVIEW QUEUE STATS: \(mcqCount) MCQs, \(openEndedCount) Open-ended (Total: \(mcqCount + openEndedCount))")
            
            return (totalMCQs: mcqCount, totalOpenEnded: openEndedCount)
        } catch {
            print("❌ Error fetching queue statistics: \(error)")
            return (totalMCQs: 0, totalOpenEnded: 0)
        }
    }
    
    // MARK: - Mark Items as Completed
    
    func markItemsAsCompleted(_ items: [ReviewQueueItem]) {
        for item in items {
            item.isCompleted = true
        }
        
        do {
            try modelContext.save()
            print("Marked \(items.count) review items as completed")
        } catch {
            print("Error marking items as completed: \(error)")
        }
    }
    
    // MARK: - Clear Completed Items (Cleanup)
    
    func clearCompletedItems(olderThan days: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                item.isCompleted && item.addedDate < cutoffDate
            }
        )
        
        do {
            let oldCompletedItems = try modelContext.fetch(descriptor)
            for item in oldCompletedItems {
                modelContext.delete(item)
            }
            
            if !oldCompletedItems.isEmpty {
                try modelContext.save()
                print("Cleaned up \(oldCompletedItems.count) old completed review items")
            }
        } catch {
            print("Error cleaning up old review items: \(error)")
        }
    }
}