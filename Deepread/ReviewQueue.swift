import Foundation
import SwiftData

// MARK: - Review Queue Models

@Model
final class ReviewQueueItem {
    var id: UUID
    var ideaId: String
    var ideaTitle: String
    var bookTitle: String
    var bookId: String? // Prefer bookId; bookTitle kept for backward compat
    var questionType: QuestionType
    var conceptTested: String
    var difficulty: QuestionDifficulty
    var bloomCategory: BloomCategory
    var originalQuestionText: String
    // Curveball support
    var isCurveball: Bool
    var addedDate: Date
    var isCompleted: Bool
    
    init(
        ideaId: String,
        ideaTitle: String,
        bookTitle: String,
        bookId: String? = nil,
        questionType: QuestionType,
        conceptTested: String,
        difficulty: QuestionDifficulty,
        bloomCategory: BloomCategory,
        originalQuestionText: String,
        isCurveball: Bool = false
    ) {
        self.id = UUID()
        self.ideaId = ideaId
        self.ideaTitle = ideaTitle
        self.bookTitle = bookTitle
        self.bookId = bookId
        self.questionType = questionType
        self.conceptTested = conceptTested
        self.difficulty = difficulty
        self.bloomCategory = bloomCategory
        self.originalQuestionText = originalQuestionText
        self.isCurveball = isCurveball
        self.addedDate = Date()
        self.isCompleted = false
    }
}

// MARK: - Review Queue Manager

@MainActor
class ReviewQueueManager {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Add Mistakes to Queue
    
    func addMistakesToQueue(from attempt: TestAttempt, test: Test, idea: Idea) {
        let incorrectResponses = attempt.responses.filter { !$0.isCorrect }
        addMistakesToQueue(fromResponses: incorrectResponses, test: test, idea: idea)
    }

    /// Adds mistakes from a raw list of responses without requiring a TestAttempt container
    func addMistakesToQueue(fromResponses incorrectResponses: [QuestionResponse], test: Test, idea: Idea) {
        
        for response in incorrectResponses {
            // Find the original question
            guard let question = test.questions.first(where: { $0.id == response.questionId }) else {
                continue
            }
            // Skip if a similar pending item already exists (dedupe by concept and type)
            let conceptKey = "\(question.bloomCategory.rawValue)-\(question.difficulty.rawValue)"
            let targetIdeaId = idea.id
            let targetType = question.type
            let dupDescriptor = FetchDescriptor<ReviewQueueItem>(
                predicate: #Predicate<ReviewQueueItem> { item in
                    (item.isCompleted == false) && (item.isCurveball == false) && item.ideaId == targetIdeaId && item.conceptTested == conceptKey && item.questionType == targetType
                }
            )
            if let existing = try? modelContext.fetch(dupDescriptor), !existing.isEmpty {
                continue
            }
            
            // Create a review queue item for this mistake
            // Try to determine bookId for reliability
            let computedBookId: String? = idea.book?.id.uuidString
            let queueItem = ReviewQueueItem(
                ideaId: idea.id,
                ideaTitle: idea.title,
                bookTitle: idea.bookTitle,
                bookId: computedBookId,
                questionType: question.type,
                conceptTested: conceptKey,
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
    
    func getDailyReviewItems(bookId: String) -> (mcqs: [ReviewQueueItem], openEnded: [ReviewQueueItem]) {
        let targetBookId = bookId
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                !item.isCompleted && (item.bookId == targetBookId)
            },
            sortBy: [SortDescriptor(\.addedDate)]
        )
        
        do {
            let allPendingItems = try modelContext.fetch(descriptor)
            print("🔍 REVIEW QUEUE: pending items for book=\(bookId): \(allPendingItems.count)")

            // Curveball prioritization: pick at most 1 curveball first
            let curveballSelected: ReviewQueueItem? = allPendingItems.first(where: { $0.isCurveball })

            // Separate by type for remaining slots
            var remaining = allPendingItems
            if let selected = curveballSelected {
                remaining.removeAll { $0.id == selected.id }
            }

            // Deduplicate by (ideaId + conceptTested) within each type using simple loops
            var seenConceptsMCQ = Set<String>()
            var mcqPool: [ReviewQueueItem] = []
            for item in remaining where item.questionType == .mcq {
                let key = "\(item.ideaId)|\(item.conceptTested)"
                if seenConceptsMCQ.contains(key) { continue }
                seenConceptsMCQ.insert(key)
                mcqPool.append(item)
            }

            var seenConceptsOEQ = Set<String>()
            var openPool: [ReviewQueueItem] = []
            for item in remaining where item.questionType == .openEnded {
                let key = "\(item.ideaId)|\(item.conceptTested)"
                if seenConceptsOEQ.contains(key) { continue }
                seenConceptsOEQ.insert(key)
                openPool.append(item)
            }

            // Apply daily limits: up to 3 MCQs and max 1 OEQ (total max 4)
            var selectedMCQs: [ReviewQueueItem] = []
            var selectedOpen: [ReviewQueueItem] = []

            // If curveball exists, allocate into the right bucket and reduce quota
            if let selected = curveballSelected {
                if selected.questionType == .openEnded {
                    selectedOpen.append(selected)
                } else if selected.questionType == .mcq {
                    selectedMCQs.append(selected)
                }
            }

            // Fill remaining respecting caps
            let mcqRemainingCap = max(0, 3 - selectedMCQs.count)
            let openRemainingCap = max(0, 1 - selectedOpen.count)

            // Avoid re-adding the same concept as the curveball
            var usedKeys = Set<String>()
            if let selected = curveballSelected {
                let key = "\(selected.ideaId)|\(selected.conceptTested)"
                usedKeys.insert(key)
            }

            for item in mcqPool {
                if selectedMCQs.count >= mcqRemainingCap { break }
                let key = "\(item.ideaId)|\(item.conceptTested)"
                if usedKeys.contains(key) { continue }
                selectedMCQs.append(item)
                usedKeys.insert(key)
            }
            for item in openPool {
                if selectedOpen.count >= openRemainingCap { break }
                let key = "\(item.ideaId)|\(item.conceptTested)"
                if usedKeys.contains(key) { continue }
                selectedOpen.append(item)
                usedKeys.insert(key)
            }

            print("🔍 REVIEW QUEUE: selected for today → MCQ=\(selectedMCQs.count), OEQ=\(selectedOpen.count)")
            return (mcqs: selectedMCQs, openEnded: selectedOpen)
        } catch {
            print("Error fetching review queue items: \(error)")
            return (mcqs: [], openEnded: [])
        }
    }
    
    // MARK: - Get Queue Statistics
    
    func getQueueStatistics(bookId: String) -> (totalMCQs: Int, totalOpenEnded: Int) {
        print("🔍 REVIEW QUEUE: getQueueStatistics() called for bookId: \(bookId)")
        let targetBookId = bookId
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                !item.isCompleted && (item.bookId == targetBookId)
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
    
    // (Removed clearCompletedItems; not used in app flows)
}
