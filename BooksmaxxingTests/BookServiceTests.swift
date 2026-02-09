import Testing
@testable import Booksmaxxing
import SwiftData

@MainActor
struct BookServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Book.self, Idea.self)
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
        let oldLastAccessed = Date().addingTimeInterval(-600)
        book.lastAccessed = oldLastAccessed
        context.insert(book)
        try context.save()

        let updated = service.markBookAsRecentlyUsed(book, minimumInterval: 120)

        #expect(updated == true)
        #expect(book.lastAccessed > oldLastAccessed)
    }

    @Test
    func markBookAsRecentlyUsedSkipsWhenBelowThreshold() async throws {
        let context = try makeContext()
        let service = BookService(modelContext: context)

        let book = Book(title: "Atomic Habits", author: "James Clear")
        let recentTimestamp = Date().addingTimeInterval(-30)
        book.lastAccessed = recentTimestamp
        context.insert(book)
        try context.save()

        let updated = service.markBookAsRecentlyUsed(book, minimumInterval: 120)

        #expect(updated == false)
        #expect(book.lastAccessed == recentTimestamp)
    }
}
