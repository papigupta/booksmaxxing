import Foundation
import SwiftData

// MARK: - Review Queue Models

@Model
final class ReviewQueueItem {
    var id: UUID = UUID()
    var ideaId: String = ""
    var ideaTitle: String = ""
    var bookTitle: String = ""
    var bookId: String? // Prefer bookId; bookTitle kept for backward compat
    var questionType: QuestionType = QuestionType.mcq
    var conceptTested: String = ""
    var difficulty: QuestionDifficulty = QuestionDifficulty.easy
    var bloomCategory: BloomCategory = BloomCategory.recall
    var originalQuestionText: String = ""
    // Curveball support
    var isCurveball: Bool = false
    // Spaced follow-up support
    var isSpacedFollowUp: Bool = false
    var addedDate: Date = Date.now
    var isCompleted: Bool = false
    
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
        isCurveball: Bool = false,
        isSpacedFollowUp: Bool = false
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
        self.isSpacedFollowUp = isSpacedFollowUp
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
        let incorrectResponses = (attempt.responses ?? []).filter { !$0.isCorrect }
        addMistakesToQueue(fromResponses: incorrectResponses, test: test, idea: idea)
    }

    /// Adds mistakes from a raw list of responses without requiring a TestAttempt container
    func addMistakesToQueue(fromResponses incorrectResponses: [QuestionResponse], test: Test, idea: Idea) {
        
        for response in incorrectResponses {
            // Find the original question
            guard let question = (test.questions ?? []).first(where: { $0.id == response.questionId }) else {
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
    
    func getDailyReviewItems(
        bookId: String,
        bookTitle: String? = nil,
        mcqCap: Int = 3,
        openCap: Int = 1
    ) -> (mcqs: [ReviewQueueItem], openEnded: [ReviewQueueItem]) {
        let targetBookId = bookId
        let hasLegacyTitle = bookTitle != nil
        let safeLegacyTitle = bookTitle ?? ""
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                !item.isCompleted && (
                    item.bookId == targetBookId ||
                    (hasLegacyTitle && item.bookId == nil && item.bookTitle == safeLegacyTitle)
                )
            },
            sortBy: [SortDescriptor(\.addedDate)]
        )
        
        do {
            let allPendingItems = try modelContext.fetch(descriptor)
            print("🔍 REVIEW QUEUE: pending items for book=\(bookId): \(allPendingItems.count)")

            // OEQ prioritization: pick at most 1 OEQ in this order:
            // 1) Curveball  2) SpacedFollowUp  3) Mistake OEQ
            let curveballSelected: ReviewQueueItem? = allPendingItems.first(where: { $0.isCurveball })
            let spacedSelected: ReviewQueueItem? = (curveballSelected == nil)
                ? allPendingItems.first(where: { $0.isSpacedFollowUp })
                : nil

            // Separate by type for remaining slots
            var remaining = allPendingItems
            if let selected = curveballSelected ?? spacedSelected {
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

            // If OEQ priority (curveball or spacedfollowup) exists, allocate into the right bucket and reduce quota
            if let selected = curveballSelected ?? spacedSelected {
                if selected.questionType == .openEnded {
                    selectedOpen.append(selected)
                } else if selected.questionType == .mcq {
                    selectedMCQs.append(selected)
                }
            }

            // Fill remaining respecting caps
            let mcqRemainingCap = max(0, mcqCap - selectedMCQs.count)
            let openRemainingCap = max(0, openCap - selectedOpen.count)

            // Avoid re-adding the same concept as the curveball
            var usedKeys = Set<String>()
            if let selected = curveballSelected ?? spacedSelected {
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
            // Apply OEQ priority among remaining candidates: prefer spacedfollowup over mistake OEQs
            let prioritizedOpen = openPool.sorted { lhs, rhs in
                let lScore = lhs.isSpacedFollowUp ? 0 : (lhs.isCurveball ? -1 : 1)
                let rScore = rhs.isSpacedFollowUp ? 0 : (rhs.isCurveball ? -1 : 1)
                return lScore < rScore
            }
            for item in prioritizedOpen {
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
    
    func getQueueStatistics(bookId: String, bookTitle: String? = nil) -> (totalMCQs: Int, totalOpenEnded: Int) {
        print("🔍 REVIEW QUEUE: getQueueStatistics() called for bookId: \(bookId)")
        let targetBookId = bookId
        let hasLegacyTitle = bookTitle != nil
        let safeLegacyTitle = bookTitle ?? ""
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate { item in
                !item.isCompleted && (
                    item.bookId == targetBookId ||
                    (hasLegacyTitle && item.bookId == nil && item.bookTitle == safeLegacyTitle)
                )
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
