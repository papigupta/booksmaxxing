import Testing
@testable import Booksmaxxing
import SwiftData

@MainActor
struct StarterLibraryTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Book.self, Idea.self)
        return ModelContext(container)
    }

    @Test
    func seedingStarterBooksPopulatesIdeas() async throws {
        let context = try makeContext()
        let seeder = StarterBookSeeder(modelContext: context)

        let seededCount = try seeder.seedAllBooksIfNeeded()

        #expect(seededCount > 0, "Expected at least one starter book to seed.")

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)

        #expect(!books.isEmpty, "Starter seeding should produce persisted books.")
        #expect(books.allSatisfy { ($0.ideas ?? []).isEmpty == false }, "Seeded books should include starter ideas.")
    }
}
