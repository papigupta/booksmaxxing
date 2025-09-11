import Foundation
import SwiftData

final class PracticePrefetcher {
    private let modelContext: ModelContext
    private let openAIService: OpenAIService

    init(modelContext: ModelContext, openAIService: OpenAIService) {
        self.modelContext = modelContext
        self.openAIService = openAIService
    }

    // Public API: Prefetch lesson N for a book.
    func prefetchLesson(book: Book, lessonNumber: Int) {
        print("PREFETCH: Request to prefetch lesson \(lessonNumber) for book: \(book.title)")
        // Guard valid lesson number
        let sortedIdeas = book.ideas.sortedByNumericId()
        guard lessonNumber > 0, lessonNumber <= sortedIdeas.count else { return }

        let primaryIdea = sortedIdeas[lessonNumber - 1]
        let ideaId = primaryIdea.id
        let bookId = book.id.uuidString

        Task { @MainActor in

            // If a session already exists and is ready or generating, no-op
            if let existing = try? await self.fetchLatestSession(ideaId: ideaId, bookId: bookId, type: "lesson_practice") {
                if existing.status == "ready" || existing.status == "generating" {
                    print("PREFETCH: Existing session for idea \(ideaId) is \(existing.status). Skipping.")
                    return
                }
            }

            // Create a generating session as a lock (on MainActor)
            let session = PracticeSession(ideaId: ideaId, bookId: bookId, type: "lesson_practice", status: "generating", configVersion: 1)
            self.modelContext.insert(session)
            try? self.modelContext.save()
            print("PREFETCH: Created GENERATING session for idea \(ideaId)")

            do {
                // Build mixed test similar to DailyPracticeView.generatePractice()
                let testGen = TestGenerationService(openAI: openAIService, modelContext: modelContext)

                // Generate fresh 8 questions for the primary idea
                print("PREFETCH: Generating fresh questions for idea \(primaryIdea.id) …")
                let freshTest = try await testGen.generateTest(for: primaryIdea, testType: "initial")

                // Ensure curveballs are queued for this specific book
                let curveballService = CurveballService(modelContext: self.modelContext)
                curveballService.ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: book.title)

                // Pull review items (max 3 MCQ + 1 OEQ) and generate review questions
                // Access ReviewQueueManager
                let manager = ReviewQueueManager(modelContext: self.modelContext)
                let result = manager.getDailyReviewItems(bookId: bookId)
                let (mcqItems, openEndedItems) = (result.mcqs, result.openEnded)
                let allReviewItems = mcqItems + openEndedItems
                print("PREFETCH: Review queue items selected: \(allReviewItems.count)")

                let freshQuestions = freshTest.orderedQuestions
                let easyFresh = freshQuestions.filter { $0.difficulty == .easy }
                var mediumFresh = freshQuestions.filter { $0.difficulty == .medium }
                var hardFresh = freshQuestions.filter { $0.difficulty == .hard }

                // Keep invariant positions for open-ended
                if let idx = mediumFresh.firstIndex(where: { $0.bloomCategory == .reframe && $0.type == .openEnded }) {
                    let q = mediumFresh.remove(at: idx)
                    mediumFresh.append(q)
                }
                if let idx = hardFresh.firstIndex(where: { $0.bloomCategory == .howWield && $0.type == .openEnded }) {
                    let q = hardFresh.remove(at: idx)
                    hardFresh.append(q)
                }

                var reviewQuestions: [Question] = []
                if !allReviewItems.isEmpty {
                    let generated = try await testGen.generateReviewQuestionsFromQueue(allReviewItems)
                    // Sort by difficulty ascending for nicer flow
                    reviewQuestions = generated.sorted { $0.difficulty.pointValue < $1.difficulty.pointValue }
                }

                // Combine: fresh (easy→medium→hard) then review
                let combinedFresh = easyFresh + mediumFresh + hardFresh
                var allQuestions: [Question] = []
                allQuestions.append(contentsOf: combinedFresh)
                allQuestions.append(contentsOf: reviewQuestions)

                // Create mixed test and attach cloned questions in order
                let mixedTest = Test(
                    ideaId: primaryIdea.id,
                    ideaTitle: primaryIdea.title,
                    bookTitle: book.title,
                    testType: "mixed"
                )

                // Build cloned questions outside of MainActor to avoid capture warnings
                let clonedQuestions: [Question] = allQuestions.enumerated().map { (index, q) in
                    Question(
                        ideaId: q.ideaId,
                        type: q.type,
                        difficulty: q.difficulty,
                        bloomCategory: q.bloomCategory,
                        questionText: q.questionText,
                        options: q.options,
                        correctAnswers: q.correctAnswers,
                        orderIndex: index,
                        isCurveball: q.isCurveball
                    )
                }

                self.modelContext.insert(mixedTest)
                for cloned in clonedQuestions {
                    cloned.test = mixedTest
                    mixedTest.questions.append(cloned)
                    self.modelContext.insert(cloned)
                }

                session.test = mixedTest
                session.status = "ready"
                session.updatedAt = Date()
                try self.modelContext.save()
                print("PREFETCH: Session READY for idea \(ideaId) with \(clonedQuestions.count) questions")
            } catch {
                // Persist error on session
                session.status = "error"
                session.updatedAt = Date()
                session.configData = "\(error.localizedDescription)".data(using: .utf8)
                try? self.modelContext.save()
                print("PREFETCH: ERROR for idea \(ideaId): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers
    private func fetchLatestSession(ideaId: String, bookId: String, type: String) async throws -> PracticeSession? {
        return try await MainActor.run {
            let descriptor = FetchDescriptor<PracticeSession>(
                predicate: #Predicate { s in
                    s.ideaId == ideaId && s.bookId == bookId && s.type == type
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try self.modelContext.fetch(descriptor).first
        }
    }
}
