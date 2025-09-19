import Foundation
import SwiftData

enum SpacedFollowUpConfig {
    static var baseDelayDays: Int = 3
    static var retryDelayDays: Int = 2
    static var curveballAfterPassDays: Int = 5
}

@MainActor
final class SpacedFollowUpService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Queue due spacedfollowup items as ReviewQueueItem (one per idea, if not already pending)
    func ensureSpacedFollowUpsQueuedIfDue(bookId: String, bookTitle: String) {
        let targetBookId = bookId
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in c.bookId == targetBookId }
        )
        do {
            let coverages = try modelContext.fetch(descriptor).filter { $0.spacedFollowUpPassedAt == nil }
            let now = Date()
            for coverage in coverages {
                // Only when: due, 8 Bloom categories covered, and we have a chosen source Bloom
                let categoriesCovered = Set(coverage.coveredCategories).count
                guard let due = coverage.spacedFollowUpDueDate, due <= now else { continue }
                guard categoriesCovered >= 8 else { continue }
                guard let bloomRaw = coverage.spacedFollowUpBloom, !bloomRaw.isEmpty else { continue }

                // Check if a pending spacedfollowup for this idea already exists
                let targetIdeaId = coverage.ideaId
                let rqDescriptor = FetchDescriptor<ReviewQueueItem>(
                    predicate: #Predicate<ReviewQueueItem> { item in
                        (item.isCompleted == false) && (item.bookId == targetBookId) && (item.ideaId == targetIdeaId) && item.isSpacedFollowUp
                    }
                )
                if let existing = try? modelContext.fetch(rqDescriptor), existing.isEmpty == false { continue }

                // Determine bloom + difficulty; default to Reframe + Hard if missing
                let bloom: BloomCategory = BloomCategory(rawValue: bloomRaw) ?? .reframe
                let difficulty: QuestionDifficulty = QuestionDifficulty(rawValue: coverage.spacedFollowUpDifficultyRaw ?? "Hard") ?? .hard

                // Get idea title
                let ideaTitle = getIdeaTitle(for: coverage.ideaId) ?? "Idea"

                let queueItem = ReviewQueueItem(
                    ideaId: coverage.ideaId,
                    ideaTitle: ideaTitle,
                    bookTitle: bookTitle,
                    bookId: bookId,
                    questionType: .openEnded,
                    conceptTested: "\(bloom.rawValue)-\(difficulty.rawValue)",
                    difficulty: difficulty,
                    bloomCategory: bloom,
                    originalQuestionText: "Spaced follow-up for \(ideaTitle)",
                    isCurveball: false,
                    isSpacedFollowUp: true
                )
                modelContext.insert(queueItem)
            }
            try modelContext.save()
        } catch {
            print("Error queueing spaced follow-ups: \(error)")
        }
    }

    /// DEV ONLY: force all spaced follow-ups due now for a book, then enqueue
    func forceAllSpacedFollowUpsDue(bookId: String, bookTitle: String) {
        let targetBookId = bookId
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in c.bookId == targetBookId }
        )
        do {
            let coverages = try modelContext.fetch(descriptor).filter { $0.spacedFollowUpPassedAt == nil }
            let now = Date().addingTimeInterval(-60)
            for c in coverages {
                // Only force due for ideas that already have a scheduled spacedfollowup (dueDate set),
                // have 8 Bloom categories and a chosen source Bloom.
                let categoriesCovered = Set(c.coveredCategories).count
                guard categoriesCovered >= 8, (c.spacedFollowUpBloom?.isEmpty == false), c.spacedFollowUpDueDate != nil else { continue }
                c.spacedFollowUpDueDate = now
            }
            try modelContext.save()
            // Enqueue immediately
            ensureSpacedFollowUpsQueuedIfDue(bookId: bookId, bookTitle: bookTitle)
        } catch {
            print("Error forcing spaced follow-ups due: \(error)")
        }
    }

    private func getIdeaTitle(for ideaId: String) -> String? {
        let targetId = ideaId
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in idea.id == targetId }
        )
        return try? modelContext.fetch(descriptor).first?.title
    }
}
