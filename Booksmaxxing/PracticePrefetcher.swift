import Foundation
import SwiftData

final class PracticePrefetcher {
    // Treat prefetch sessions older than this as stale and safe to reset.
    static let staleInterval: TimeInterval = 5 * 60

    private let modelContext: ModelContext
    private let openAIService: OpenAIService

    init(modelContext: ModelContext, openAIService: OpenAIService) {
        self.modelContext = modelContext
        self.openAIService = openAIService
    }

    // Public API: Prefetch lesson N for a book.
    func prefetchLesson(book: Book, lessonNumber: Int, fallbackIdea: Idea? = nil) {
        Task(priority: .userInitiated) { @MainActor in
            print("PREFETCH: Request to prefetch lesson \(lessonNumber) for book: \(book.title)")
            // Guard valid lesson number
            let sortedIdeas = resolveSortedIdeas(for: book)
            let primaryIdea: Idea?
            if !sortedIdeas.isEmpty {
                guard lessonNumber > 0, lessonNumber <= sortedIdeas.count else {
                    print("PREFETCH: Invalid lesson \(lessonNumber) (ideas=\(sortedIdeas.count)); skipping")
                    return
                }
                primaryIdea = sortedIdeas[lessonNumber - 1]
            } else if lessonNumber == 1, let fallbackIdea {
                primaryIdea = fallbackIdea
                print("PREFETCH: Using fallback idea \(fallbackIdea.id) for lesson 1")
            } else {
                print("PREFETCH: No ideas available for lesson \(lessonNumber); skipping")
                return
            }

            guard let primaryIdea = primaryIdea else {
                print("PREFETCH: Missing primary idea for lesson \(lessonNumber); skipping")
                return
            }
            let ideaId = primaryIdea.id
            let bookId = book.id.uuidString
            let bookTitle = book.title
            let cutoff = Date().addingTimeInterval(-Self.staleInterval)

            // Remove stale "generating"/"error" sessions so they don't permanently block prefetch.
            purgeStaleSessions(ideaId: ideaId, bookId: bookId, cutoff: cutoff)

            let start = Date()
            // If a session already exists and is ready or actively generating, no-op.
            if let existing = try? await fetchLatestSession(ideaId: ideaId, bookId: bookId, type: "lesson_practice") {
                if existing.status == "ready" {
                    print("PREFETCH: Existing session for idea \(ideaId) is READY. Skipping.")
                    return
                } else if existing.status == "generating", existing.updatedAt >= cutoff {
                    print("PREFETCH: Existing session for idea \(ideaId) still GENERATING. Skipping.")
                    return
                } else if existing.status == "error" {
                    print("PREFETCH: Removing ERROR session for idea \(ideaId); will regenerate.")
                    modelContext.delete(existing)
                    try? modelContext.save()
                }
            }

            // Fetch the Idea by id on MainActor to avoid crossing non-sendable references
            let descriptor = FetchDescriptor<Idea>(
                predicate: #Predicate { i in i.id == ideaId }
            )
            let targetIdea: Idea? = try? modelContext.fetch(descriptor).first
            guard let targetIdea = targetIdea else {
                print("PREFETCH: Could not fetch idea \(ideaId); aborting prefetch")
                return
            }

            // Create a generating session as a lock
            let session: PracticeSession = {
                let s = PracticeSession(ideaId: ideaId, bookId: bookId, type: "lesson_practice", status: "generating", configVersion: 1)
                s.updatedAt = Date()
                modelContext.insert(s)
                try? modelContext.save()
                print("PREFETCH: Created GENERATING session for idea \(ideaId)")
                return s
            }()

            do {
                // Build mixed test similar to DailyPracticeTooltip.generatePractice()
                let testGen = TestGenerationService(openAI: openAIService, modelContext: modelContext)

                // Generate fresh 8 questions for the primary idea
                print("PREFETCH: Generating fresh questions for idea \(ideaId) …")
                let freshTest = try await testGen.generateTest(for: targetIdea, testType: "initial")

                // Ensure curveballs and spacedfollowups are queued for this specific book
                let curveballService = CurveballService(modelContext: modelContext)
                curveballService.ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: bookTitle)
                let spacedService = SpacedFollowUpService(modelContext: modelContext)
                spacedService.ensureSpacedFollowUpsQueuedIfDue(bookId: bookId, bookTitle: bookTitle)

                // Pull review items (max 3 MCQ + 1 OEQ) and generate review questions
                let manager = ReviewQueueManager(modelContext: modelContext)
                let result = manager.getDailyReviewItems(
                    bookId: bookId,
                    bookTitle: book.title
                )
                let (mcqItemsRaw, openEndedItemsRaw): ([ReviewQueueItem], [ReviewQueueItem]) = (result.mcqs, result.openEnded)
                let allReviewItems = mcqItemsRaw + openEndedItemsRaw
                print("PREFETCH: Review queue items selected: \(allReviewItems.count)")

                let freshQuestions = freshTest.orderedQuestions
                let easyFresh = freshQuestions.filter { $0.difficulty == .easy }
                let mediumFresh = freshQuestions.filter { $0.difficulty == .medium }
                var hardFresh = freshQuestions.filter { $0.difficulty == .hard }

                // Keep invariant position for the single open-ended prompt (now part of the hard bucket)
                if let idx = hardFresh.firstIndex(where: { $0.type == .openEnded }) {
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
                mixedTest.idea = targetIdea

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
                        isSpacedFollowUp: q.isSpacedFollowUp,
                        sourceQueueItemId: q.sourceQueueItemId
                    )
                }

                modelContext.insert(mixedTest)
                for cloned in clonedQuestions {
                    cloned.test = mixedTest
                    if mixedTest.questions == nil { mixedTest.questions = [] }
                    mixedTest.questions?.append(cloned)
                    modelContext.insert(cloned)
                }

                session.test = mixedTest
                session.status = "ready"
                session.updatedAt = Date()
                try? modelContext.save()
                let elapsed = Date().timeIntervalSince(start)
                print("PREFETCH: Session READY for idea \(ideaId) with \(clonedQuestions.count) questions in \(String(format: "%.2f", elapsed))s")
            } catch {
                session.status = "error"
                session.updatedAt = Date()
                session.configData = "\(error.localizedDescription)".data(using: .utf8)
                try? modelContext.save()
                print("PREFETCH: ERROR for idea \(ideaId): \(error.localizedDescription)")
            }
        }
    }

    // Phase A prewarm: generate and persist only the initial 8 questions for lesson N (no session, no reviews)
    func prewarmInitialQuestions(book: Book, lessonNumber: Int) {
        Task(priority: .userInitiated) { @MainActor in
            print("PREFETCH: Prewarm request for initial questions of lesson \(lessonNumber) for book: \(book.title)")
            let sortedIdeas = resolveSortedIdeas(for: book)
            guard lessonNumber > 0, lessonNumber <= sortedIdeas.count else {
                print("PREFETCH: Invalid prewarm lesson \(lessonNumber) (ideas=\(sortedIdeas.count)); skipping")
                return
            }

            let targetIdea = sortedIdeas[lessonNumber - 1]
            let ideaId = targetIdea.id

            // If an initial test already exists with >=8 questions, skip
            let descriptor = FetchDescriptor<Test>(
                predicate: #Predicate<Test> { t in t.ideaId == ideaId && t.testType == "initial" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let hasInitial: Bool = {
                if let existing = try? modelContext.fetch(descriptor).first { return (existing.questions ?? []).count >= 8 }
                return false
            }()
            if hasInitial {
                print("PREFETCH: Initial 8 already present for idea \(ideaId); skipping prewarm")
                return
            }

            // Generate and store the initial 8 test so later calls hit cache
            let testGen = TestGenerationService(openAI: openAIService, modelContext: modelContext)
            // Fetch Idea on main actor to avoid crossing non-sendable references
            let descriptorIdea = FetchDescriptor<Idea>(predicate: #Predicate<Idea> { $0.id == ideaId })
            let idea: Idea? = try? modelContext.fetch(descriptorIdea).first
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

    private func purgeStaleSessions(ideaId: String, bookId: String, cutoff: Date) {
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { s in
                s.ideaId == ideaId && s.bookId == bookId && s.type == "lesson_practice"
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let sessions = try? modelContext.fetch(descriptor) else { return }
        var purged = 0
        for session in sessions {
            if (session.status == "generating" || session.status == "error"), session.updatedAt < cutoff {
                modelContext.delete(session)
                purged += 1
            }
        }
        if purged > 0 {
            try? modelContext.save()
            print("PREFETCH: Purged \(purged) stale sessions for idea \(ideaId)")
        }
    }

    @MainActor
    private func resolveSortedIdeas(for book: Book) -> [Idea] {
        let localIdeas = (book.ideas ?? []).sortedByNumericId()
        if !localIdeas.isEmpty {
            return localIdeas
        }

        let bookUUID = book.id
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == bookUUID }
        )
        if let refreshedBook = try? modelContext.fetch(descriptor).first {
            let fetchedIdeas = (refreshedBook.ideas ?? []).sortedByNumericId()
            if !fetchedIdeas.isEmpty {
                print("PREFETCH: Loaded \(fetchedIdeas.count) ideas from modelContext for book \(book.title)")
                return fetchedIdeas
            }
        }

        return []
    }
}
