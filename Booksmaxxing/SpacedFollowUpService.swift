import Foundation
import OSLog
import SwiftData

enum SpacedFollowUpConfig {
    static var baseDelayDays: Int = 3
    static var retryDelayDays: Int = 2
    static var curveballAfterPassDays: Int = 5
}

@MainActor
final class SpacedFollowUpService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.booksmaxxing.app", category: "SpacedFollowUpService")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Queue due spacedfollowup items as ReviewQueueItem (one per idea, if not already pending)
    func ensureSpacedFollowUpsQueuedIfDue(bookId: String, bookTitle: String) {
        cleanupDuplicateSpacedFollowUps(bookId: bookId, bookTitle: bookTitle)
        let targetBookId = bookId
        let normalizedTitle = ReviewQueueItem.normalizeBookTitle(bookTitle)
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in c.bookId == targetBookId }
        )
        do {
            let coverages = try modelContext.fetch(descriptor).filter { $0.spacedFollowUpPassedAt == nil }
            let now = Date()
            for coverage in coverages {
                // Only when: due, 8 total correct answers logged, and we have a chosen source Bloom
                guard let due = coverage.spacedFollowUpDueDate, due <= now else { continue }
                guard coverage.totalQuestionsCorrect >= 8 else { continue }
                guard let bloomRaw = coverage.spacedFollowUpBloom, !bloomRaw.isEmpty else { continue }

                // Check if a pending spacedfollowup for this idea already exists
                let targetIdeaId = coverage.ideaId
                let rqDescriptor = FetchDescriptor<ReviewQueueItem>(
                    predicate: #Predicate<ReviewQueueItem> { item in
                        item.isSpacedFollowUp && item.ideaId == targetIdeaId && (item.bookId == targetBookId || item.bookId == nil)
                    }
                )
                if let fetched = try? modelContext.fetch(rqDescriptor) {
                    let existing = fetched.filter { $0.matchesBook(targetBookId: targetBookId, normalizedBookTitle: normalizedTitle) }
                    if existing.isEmpty == false {
                        if existing.count > 1 {
                            logger.warning("Scheduler detected \(existing.count) pending SPFUs for idea=\(targetIdeaId, privacy: .public)")
                        }
                        continue
                    }
                }

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
        cleanupDuplicateSpacedFollowUps(bookId: bookId, bookTitle: bookTitle)
        let targetBookId = bookId
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in c.bookId == targetBookId }
        )
        do {
            let coverages = try modelContext.fetch(descriptor).filter { $0.spacedFollowUpPassedAt == nil }
            let now = Date().addingTimeInterval(-60)
            for c in coverages {
                // Only force due for ideas that already have a scheduled spacedfollowup (dueDate set),
                // have at least 8 correct answers and a chosen source Bloom.
                guard c.totalQuestionsCorrect >= 8, (c.spacedFollowUpBloom?.isEmpty == false), c.spacedFollowUpDueDate != nil else { continue }
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

    private func cleanupDuplicateSpacedFollowUps(bookId: String, bookTitle: String) {
        let normalizedTitle = ReviewQueueItem.normalizeBookTitle(bookTitle)
        let descriptor = FetchDescriptor<ReviewQueueItem>(
            predicate: #Predicate {
                $0.isSpacedFollowUp && ($0.bookId == bookId || $0.bookId == nil)
            },
            sortBy: [SortDescriptor(\.ideaId), SortDescriptor(\.addedDate)]
        )

        guard let rawItems = try? modelContext.fetch(descriptor), rawItems.isEmpty == false else { return }
        let queueItems = rawItems.filter { $0.matchesBook(targetBookId: bookId, normalizedBookTitle: normalizedTitle) }
        guard queueItems.isEmpty == false else { return }

        let coverageDescriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { $0.bookId == bookId }
        )
        let coverages = (try? modelContext.fetch(coverageDescriptor)) ?? []
        let coverageByIdea = Dictionary(uniqueKeysWithValues: coverages.map { ($0.ideaId, $0) })

        var grouped: [String: [ReviewQueueItem]] = [:]
        var didMutate = false
        for item in queueItems {
            // Backfill normalized titles/book IDs for legacy rows
            let normalized = item.bookTitleNormalized ?? ReviewQueueItem.normalizeBookTitle(item.bookTitle)
            if item.bookTitleNormalized != normalized {
                item.bookTitleNormalized = normalized
                didMutate = true
            }
            if item.bookId == nil && normalized == normalizedTitle {
                item.bookId = bookId
                didMutate = true
            }
            grouped[item.ideaId, default: []].append(item)
        }

        for (ideaId, items) in grouped {
            guard let coverage = coverageByIdea[ideaId] else { continue }
            // If coverage already passed SPFU, mark any lingering entries completed
            if coverage.spacedFollowUpPassedAt != nil {
                for entry in items where entry.isCompleted == false {
                    entry.isCompleted = true
                    didMutate = true
                }
                continue
            }

            let pending = items.filter { $0.isCompleted == false }
            if pending.count <= 1 { continue }

            logger.warning("Cleanup resolved \(pending.count) pending SPFUs for idea=\(ideaId, privacy: .public)")
            let sortedPending = pending.sorted { $0.addedDate < $1.addedDate }
            for entry in sortedPending.dropFirst() {
                entry.isCompleted = true
                didMutate = true
            }
        }

        if didMutate {
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save SPFU cleanup for book=\(bookId, privacy: .public): \(String(describing: error))")
            }
        }
    }
}
