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
        let bookTitle = book.title

        Task.detached { [modelContext, openAIService] in
            let start = Date()
            // If a session already exists and is ready or generating, no-op
            let existing: PracticeSession? = await MainActor.run { () -> PracticeSession? in
                do {
                    let descriptor = FetchDescriptor<PracticeSession>(
                        predicate: #Predicate { s in
                            s.ideaId == ideaId && s.bookId == bookId && s.type == "lesson_practice"
                        },
                        sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                    )
                    return try modelContext.fetch(descriptor).first
                } catch { return nil }
            }
            if let existing = existing {
                if existing.status == "ready" || existing.status == "generating" {
                    print("PREFETCH: Existing session for idea \(ideaId) is \(existing.status). Skipping.")
                    return
                }
            }

            // Create a generating session as a lock
            let session: PracticeSession = await MainActor.run {
                let s = PracticeSession(ideaId: ideaId, bookId: bookId, type: "lesson_practice", status: "generating", configVersion: 1)
                modelContext.insert(s)
                try? modelContext.save()
                print("PREFETCH: Created GENERATING session for idea \(ideaId)")
                return s
            }

            do {
                // Build mixed test similar to DailyPracticeView.generatePractice()
                let testGen = await MainActor.run { TestGenerationService(openAI: openAIService, modelContext: modelContext) }

                // Fetch the Idea by id on MainActor to avoid crossing non-sendable references
                let targetIdea: Idea? = await MainActor.run { () -> Idea? in
                    let descriptor = FetchDescriptor<Idea>(
                        predicate: #Predicate { i in i.id == ideaId }
                    )
                    return try? modelContext.fetch(descriptor).first
                }
                guard let targetIdea = targetIdea else {
                    print("PREFETCH: Could not fetch idea \(ideaId); aborting prefetch")
                    return
                }

                // Generate fresh 8 questions for the primary idea
                print("PREFETCH: Generating fresh questions for idea \(ideaId) …")
                let freshTest = try await testGen.generateTest(for: targetIdea, testType: "initial")

                // Ensure curveballs are queued for this specific book
                await MainActor.run {
                    let curveballService = CurveballService(modelContext: modelContext)
                    curveballService.ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: bookTitle)
                }

                // Pull review items (max 3 MCQ + 1 OEQ) and generate review questions
                let (mcqItemsRaw, openEndedItemsRaw): ([ReviewQueueItem], [ReviewQueueItem]) = await MainActor.run {
                    let manager = ReviewQueueManager(modelContext: modelContext)
                    let result = manager.getDailyReviewItems(bookId: bookId)
                    return (result.mcqs, result.openEnded)
                }
                let allReviewItems = mcqItemsRaw + openEndedItemsRaw
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
                    // Preserve association via sourceQueueItemId set in generation; sort by difficulty for nicer flow.
                    reviewQuestions = generated.sorted { $0.difficulty.pointValue < $1.difficulty.pointValue }
                }

                // Combine: fresh (easy→medium→hard) then review
                let combinedFresh = easyFresh + mediumFresh + hardFresh
                var allQuestions: [Question] = []
                allQuestions.append(contentsOf: combinedFresh)
                allQuestions.append(contentsOf: reviewQuestions)

                // Create mixed test and attach cloned questions in order
                let mixedTest = Test(
                    ideaId: ideaId,
                    ideaTitle: targetIdea.title,
                    bookTitle: bookTitle,
                    testType: "mixed"
                )

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
                        isCurveball: q.isCurveball,
                        sourceQueueItemId: q.sourceQueueItemId
                    )
                }

                await MainActor.run {
                    modelContext.insert(mixedTest)
                    for cloned in clonedQuestions {
                        cloned.test = mixedTest
                        mixedTest.questions.append(cloned)
                        modelContext.insert(cloned)
                    }

                    session.test = mixedTest
                    session.status = "ready"
                    session.updatedAt = Date()
                    try? modelContext.save()
                    let elapsed = Date().timeIntervalSince(start)
                    print("PREFETCH: Session READY for idea \(ideaId) with \(clonedQuestions.count) questions in \(String(format: "%.2f", elapsed))s")
                }
            } catch {
                await MainActor.run {
                    session.status = "error"
                    session.updatedAt = Date()
                    session.configData = "\(error.localizedDescription)".data(using: .utf8)
                    try? modelContext.save()
                    print("PREFETCH: ERROR for idea \(ideaId): \(error.localizedDescription)")
                }
            }
        }
    }

    // Phase A prewarm: generate and persist only the initial 8 questions for lesson N (no session, no reviews)
    func prewarmInitialQuestions(book: Book, lessonNumber: Int) {
        print("PREFETCH: Prewarm request for initial questions of lesson \(lessonNumber) for book: \(book.title)")
        let sortedIdeas = book.ideas.sortedByNumericId()
        guard lessonNumber > 0, lessonNumber <= sortedIdeas.count else { return }

        let targetIdea = sortedIdeas[lessonNumber - 1]
        let ideaId = targetIdea.id

        Task.detached { [modelContext, openAIService] in
            // If an initial test already exists with >=8 questions, skip
            let hasInitial: Bool = await MainActor.run {
                let descriptor = FetchDescriptor<Test>(
                    predicate: #Predicate<Test> { t in t.ideaId == ideaId && t.testType == "initial" },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                if let existing = try? modelContext.fetch(descriptor).first { return existing.questions.count >= 8 }
                return false
            }
            if hasInitial {
                print("PREFETCH: Initial 8 already present for idea \(ideaId); skipping prewarm")
                return
            }

            // Generate and store the initial 8 test so later calls hit cache
            let testGen = await MainActor.run { TestGenerationService(openAI: openAIService, modelContext: modelContext) }
            // Fetch Idea on main actor to avoid crossing non-sendable references
            let idea: Idea? = await MainActor.run { () -> Idea? in
                let descriptor = FetchDescriptor<Idea>(predicate: #Predicate<Idea> { $0.id == ideaId })
                return try? modelContext.fetch(descriptor).first
            }
            guard let idea = idea else {
                print("PREFETCH: Could not fetch idea for prewarm \(ideaId)")
                return
            }
            do {
                _ = try await testGen.generateTest(for: idea, testType: "initial")
                print("PREFETCH: Prewarmed initial 8 for idea \(ideaId)")
            } catch {
                print("PREFETCH: Failed to prewarm initial 8 for idea \(ideaId): \(error.localizedDescription)")
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
