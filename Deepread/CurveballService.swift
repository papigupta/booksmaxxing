import Foundation
import SwiftData

// MARK: - Curveball Configuration
enum CurveballConfig {
    // Default delay in days (configurable later via settings)
    static var delayDays: Int = 3
}

// MARK: - Curveball Scheduling and Generation Helper
@MainActor
final class CurveballService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Ensure that due curveballs are queued as review items for the given book.
    /// This creates at most one pending curveball ReviewQueueItem per fully covered idea that is due and not already queued.
    func ensureCurveballsQueuedIfDue(bookId: String, bookTitle: String) {
        let targetBookId = bookId
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in
                c.bookId == targetBookId && c.isFullyCovered && (c.curveballPassed == false)
            }
        )

        do {
            let coverages = try modelContext.fetch(descriptor)
            let now = Date()

            for coverage in coverages {
                // If not scheduled yet, schedule based on coveredDate
                if coverage.curveballDueDate == nil {
                    let base = coverage.coveredDate ?? now
                    coverage.curveballDueDate = Calendar.current.date(byAdding: .day, value: CurveballConfig.delayDays, to: base)
                }
                guard let due = coverage.curveballDueDate, due <= now else { continue }

                // Check if a pending curveball for this idea already exists
                let targetBookTitle = bookTitle
                let targetIdeaId = coverage.ideaId
                let rqDescriptor = FetchDescriptor<ReviewQueueItem>(
                    predicate: #Predicate<ReviewQueueItem> { item in
                        (item.isCompleted == false) && item.bookTitle == targetBookTitle && item.ideaId == targetIdeaId && item.isCurveball
                    }
                )
                let existing = try modelContext.fetch(rqDescriptor)
                if !existing.isEmpty { continue }

                // Decide curveball spec based on mistake history
                let (bloom, type) = selectCurveballSpec(for: coverage)
                let difficulty: QuestionDifficulty = .hard

                // Get idea title for context
                let ideaTitle = getIdeaTitle(for: coverage.ideaId) ?? "Idea"

                // Seed text—either last missed question in that bloom or a generic seed
                var seedText = latestMissedQuestion(for: coverage, bloomRaw: bloom.rawValue) ?? "Curveball validation for \(ideaTitle)"
                if isPoorSeed(seedText) {
                    seedText = "Curveball validation for \(ideaTitle)"
                }

                let queueItem = ReviewQueueItem(
                    ideaId: coverage.ideaId,
                    ideaTitle: ideaTitle,
                    bookTitle: bookTitle,
                    bookId: bookId,
                    questionType: type,
                    conceptTested: "\(bloom.rawValue)-\(difficulty.rawValue)",
                    difficulty: difficulty,
                    bloomCategory: bloom,
                    originalQuestionText: seedText,
                    isCurveball: true
                )
                modelContext.insert(queueItem)
            }

            try modelContext.save()
        } catch {
            print("Error scheduling curveballs: \(error)")
        }
    }

    // MARK: - Helpers
    private func isPoorSeed(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 20 { return true }
        let lower = trimmed.lowercased()
        let banned = ["all of the above", "none of the above", "both a and b", "option 1", "option one", "placeholder"]
        return banned.contains { lower.contains($0) }
    }
    private func selectCurveballSpec(for coverage: IdeaCoverage) -> (BloomCategory, QuestionType) {
        // Case 1: 100% accuracy path — no mistakes ever recorded
        if coverage.mistakesCount == 0 {
            // Choose the highest-order check
            return (.howWield, .openEnded)
        }

        // Case 2: Less than 100% accuracy at some point — pick category with highest retryCount
        let mostRetried = (coverage.missedQuestions ?? []).max { lhs, rhs in
            lhs.retryCount < rhs.retryCount
        }
        if let concept = mostRetried?.conceptTested,
           let raw = concept.split(separator: "-").first.map(String.init),
           let bloom = BloomCategory(rawValue: raw) {
            // Choose type: OEQ for high-level categories, otherwise MCQ
            let type: QuestionType = (bloom == .howWield || bloom == .reframe) ? .openEnded : .mcq
            return (bloom, type)
        }

        // Fallback
        return (.howWield, .openEnded)
    }

    private func latestMissedQuestion(for coverage: IdeaCoverage, bloomRaw: String) -> String? {
        // Find the most recent missed question text for that bloom category
        return (coverage.missedQuestions ?? [])
            .reversed()
            .first(where: { $0.conceptTested.hasPrefix(bloomRaw) })?
            .questionText
    }

    private func getIdeaTitle(for ideaId: String) -> String? {
        let targetId = ideaId
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in idea.id == targetId }
        )
        return try? modelContext.fetch(descriptor).first?.title
    }

    // Mark curveball result on coverage and optionally bump mastery
    func markCurveballResult(ideaId: String, bookId: String, passed: Bool) {
        let targetIdeaId = ideaId
        let targetBookId = bookId
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in
                c.ideaId == targetIdeaId && c.bookId == targetBookId
            }
        )
        do {
            if let coverage = try modelContext.fetch(descriptor).first {
                if passed {
                    coverage.curveballPassed = true
                    coverage.curveballPassedAt = Date()
                } else {
                    // Re-schedule in configured days
                    let days = CurveballConfig.delayDays
                    coverage.curveballDueDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
                }
                try modelContext.save()
            }
        } catch {
            print("Error updating curveball result: \(error)")
        }
    }

    /// DEV ONLY: force all due dates to now and queue curveballs for test
    func forceAllCurveballsDue(bookId: String, bookTitle: String) {
        let targetBookId = bookId
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate<IdeaCoverage> { c in
                c.bookId == targetBookId && c.isFullyCovered && (c.curveballPassed == false)
            }
        )
        do {
            let coverages = try modelContext.fetch(descriptor)
            let now = Date()
            for c in coverages {
                c.curveballDueDate = now.addingTimeInterval(-60)
            }
            try modelContext.save()
            // Queue immediately
            ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: bookTitle)
        } catch {
            print("Error forcing curveballs due: \(error)")
        }
    }
}
