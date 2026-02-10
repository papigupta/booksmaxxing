import Testing
@testable import Booksmaxxing
import SwiftData
import Foundation

@MainActor
struct BookServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Book.self, Idea.self)
        return ModelContext(container)
    }

    private func makeResetContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self,
                 Idea.self,
                 Booksmaxxing.Progress.self,
                 Primer.self,
                 PrimerLinkItem.self,
                 Question.self,
                 Booksmaxxing.Test.self,
                 TestAttempt.self,
                 QuestionResponse.self,
                 TestProgress.self,
                 PracticeSession.self,
                 ReviewQueueItem.self,
                 IdeaCoverage.self,
                 MissedQuestionRecord.self,
                 StoredLesson.self,
                 BookTheme.self,
                 UserProfile.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @Test
    func saveIdeasAssignsBookSpecificIdsAndSorts() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let book = Book(title: "Test Book", author: "Author")
        book.bookNumber = 1
        context.insert(book)

        let ideaB = Idea(id: "i2", title: "Second", description: "desc", bookTitle: book.title, depthTarget: 1)
        let ideaA = Idea(id: "i1", title: "First", description: "desc", bookTitle: book.title, depthTarget: 1)

        try service.saveIdeas([ideaB, ideaA], for: book)

        let fetched = try service.getBook(withTitle: "Test Book")
        #expect(fetched != nil)
        let ids = fetched?.ideas?.map { $0.id } ?? []
        #expect(ids == ["b1i1", "b1i2"])
    }

    @Test
    func cleanupDuplicateBooksRemovesIdeaLessDuplicates() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let main = Book(title: "Atomic Habits", author: "James Clear")
        main.bookNumber = 1
        context.insert(main)
        let idea = Idea(id: "i1", title: "Tiny Habits", description: "desc", bookTitle: main.title, depthTarget: 1)
        try service.saveIdeas([idea], for: main)

        let duplicate = Book(title: "Atomic", author: nil)
        duplicate.bookNumber = 2
        context.insert(duplicate)
        try context.save()

        try service.cleanupDuplicateBooks()

        let descriptor = FetchDescriptor<Book>()
        let all = try context.fetch(descriptor)
        #expect(all.count == 1)
        #expect(all.first?.title == "Atomic Habits")
    }

    @Test
    func markBookAsRecentlyUsedUpdatesWhenThresholdPassed() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let book = Book(title: "Deep Work", author: "Cal Newport")
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        let oldLastAccessed = now.addingTimeInterval(-600)
        book.lastAccessed = oldLastAccessed
        context.insert(book)
        try context.save()

        let updated = service.markBookAsRecentlyUsed(book, minimumInterval: 120, now: now)

        #expect(updated == true)
        #expect(book.lastAccessed == now)
    }

    @Test
    func markBookAsRecentlyUsedSkipsWhenBelowThreshold() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let book = Book(title: "Atomic Habits", author: "James Clear")
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        let recentTimestamp = now.addingTimeInterval(-30)
        book.lastAccessed = recentTimestamp
        context.insert(book)
        try context.save()

        let updated = service.markBookAsRecentlyUsed(book, minimumInterval: 120, now: now)

        #expect(updated == false)
        #expect(book.lastAccessed == recentTimestamp)
    }

    @Test
    func markBookAsRecentlyUsedCorrectsFutureClockSkew() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let book = Book(title: "The Lean Startup", author: "Eric Ries")
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        book.lastAccessed = now.addingTimeInterval(600)
        context.insert(book)
        try context.save()

        let updated = service.markBookAsRecentlyUsed(book, minimumInterval: 120, now: now)

        #expect(updated == true)
        #expect(book.lastAccessed == now)
    }

    @Test
    func sortedByRecentUsageUsesStableTieBreakers() {
        let timestamp = Date(timeIntervalSince1970: 1_735_000_000)

        let beta = Book(title: "beta")
        beta.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        beta.createdAt = timestamp
        beta.lastAccessed = timestamp
        beta.bookNumber = 1

        let alpha = Book(title: "Alpha")
        alpha.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        alpha.createdAt = timestamp
        alpha.lastAccessed = timestamp
        alpha.bookNumber = 1

        let sorted = BookService.sortedByRecentUsage([beta, alpha])
        #expect(sorted.map(\.title) == ["Alpha", "beta"])
        #expect(sorted.map(\.id.uuidString) == [
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002"
        ])
    }

    @Test
    func findOrCreateBookDoesNotReusePartialTitleMatches() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let existing = Book(title: "Thinking, Fast and Slow (Special Edition)")
        existing.bookNumber = 1
        context.insert(existing)
        try context.save()

        let created = try service.findOrCreateBook(
            title: "Thinking, Fast and Slow",
            author: "Daniel Kahneman",
            triggerMetadataFetch: false
        )

        #expect(created.id != existing.id)
        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 2)
    }

    @Test
    func getBookUsesCanonicalExactTitleMatching() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let target = Book(title: "  Antifragile  ")
        target.bookNumber = 1
        context.insert(target)
        try context.save()

        let exact = try service.getBook(withTitle: "antifragile")
        #expect(exact?.id == target.id)

        let partial = try service.getBook(withTitle: "anti")
        #expect(partial == nil)
    }

    @Test
    func resetAllBookDataRemovesBookDomainModelsButKeepsUserProfile() async throws {
        let context = try makeResetContext()
        let service = BookService(modelContext: context)

        let profile = UserProfile(name: "Existing Account")
        context.insert(profile)

        let book = Book(title: "Reset Candidate", author: "Tester")
        book.bookNumber = 1
        context.insert(book)

        let idea = Idea(id: "i1", title: "Core Idea", description: "desc", bookTitle: book.title, depthTarget: 1)
        idea.book = book
        book.ideas = [idea]
        context.insert(idea)

        let progress = Booksmaxxing.Progress(ideaId: idea.id, level: 1, score: 10)
        progress.idea = idea
        idea.progress = [progress]
        context.insert(progress)

        let primer = Primer(ideaId: idea.id, overview: "overview", keyNuances: [], digDeeperLinks: [])
        primer.idea = idea
        idea.primer = primer
        context.insert(primer)

        let primerLink = PrimerLinkItem(title: "Docs", url: "https://example.com")
        primerLink.primer = primer
        primer.links = [primerLink]
        context.insert(primerLink)

        let testProgress = TestProgress(ideaId: idea.id)
        testProgress.idea = idea
        idea.testProgresses = [testProgress]
        context.insert(testProgress)

        let test = Booksmaxxing.Test(ideaId: idea.id, ideaTitle: idea.title, bookTitle: book.title)
        test.idea = idea
        idea.tests = [test]
        context.insert(test)

        let question = Question(
            ideaId: idea.id,
            type: .mcq,
            difficulty: .easy,
            bloomCategory: .recall,
            questionText: "Question?",
            options: ["A", "B"],
            correctAnswers: [0],
            orderIndex: 0
        )
        question.test = test
        test.questions = [question]
        context.insert(question)

        let attempt = TestAttempt(testId: test.id)
        attempt.test = test
        test.attempts = [attempt]
        context.insert(attempt)

        let response = QuestionResponse(
            attemptId: attempt.id,
            questionId: question.id,
            questionType: .mcq,
            userAnswer: "0",
            isCorrect: true,
            pointsEarned: 10
        )
        response.attempt = attempt
        response.question = question
        attempt.responses = [response]
        question.responses = [response]
        context.insert(response)

        let session = PracticeSession(ideaId: idea.id, bookId: book.id.uuidString, type: "lesson_practice")
        session.test = test
        test.practiceSession = session
        context.insert(session)

        let queueItem = ReviewQueueItem(
            ideaId: idea.id,
            ideaTitle: idea.title,
            bookTitle: book.title,
            bookId: book.id.uuidString,
            questionType: .mcq,
            conceptTested: "Recall-Easy",
            difficulty: .easy,
            bloomCategory: .recall,
            originalQuestionText: "Original question"
        )
        context.insert(queueItem)

        let coverage = IdeaCoverage(ideaId: idea.id, bookId: book.id.uuidString)
        let missed = MissedQuestionRecord(
            originalQuestionId: question.id.uuidString,
            questionText: question.questionText,
            conceptTested: "Recall-Easy",
            attemptDate: Date()
        )
        missed.coverage = coverage
        coverage.missedQuestions = [missed]
        context.insert(coverage)
        context.insert(missed)

        let storedLesson = StoredLesson(
            bookId: book.id.uuidString,
            lessonNumber: 1,
            primaryIdeaId: idea.id,
            primaryIdeaTitle: idea.title
        )
        context.insert(storedLesson)

        let theme = BookTheme(bookId: book.id, seedHex: "#ffffff", rolesJSON: Data("{}".utf8))
        context.insert(theme)

        try context.save()

        let report = try service.resetAllBookData()

        #expect(report.requestedBookCount == 1)
        #expect(report.deletedBookCount == 1)
        #expect(report.failedBooks.isEmpty)
        #expect(report.residualEntityCounts.isEmpty)
        #expect(report.isSuccessful == true)

        #expect(try context.fetch(FetchDescriptor<Book>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Idea>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Booksmaxxing.Progress>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Primer>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PrimerLinkItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Booksmaxxing.Test>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Question>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TestAttempt>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QuestionResponse>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TestProgress>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PracticeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredLesson>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReviewQueueItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<IdeaCoverage>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BookTheme>()).isEmpty)

        let remainingProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(remainingProfiles.count == 1)
        #expect(remainingProfiles.first?.name == "Existing Account")
    }
}
