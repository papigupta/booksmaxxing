import Foundation
import SwiftData

@MainActor
struct StarterBookSeeder {
    private let bookService: BookService

    init(modelContext: ModelContext) {
        self.bookService = BookService(modelContext: modelContext)
    }

    func seedAllBooksIfNeeded() throws -> Bool {
        let seeds = try StarterLibrary.shared.books()
        var didSeedAnything = false
        for seed in seeds {
            let seeded = try seedBookIfNeeded(seed)
            didSeedAnything = didSeedAnything || seeded
        }
        return didSeedAnything
    }

    private func seedBookIfNeeded(_ seed: StarterBookSeed) throws -> Bool {
        let book = try bookService.findOrCreateBook(
            title: seed.title,
            author: seed.author,
            triggerMetadataFetch: false
        )

        if let existingIdeas = book.ideas, !existingIdeas.isEmpty {
            return false
        }

        book.bookDescription = seed.description
        book.thumbnailUrl = seed.thumbnailUrl
        book.coverImageUrl = seed.coverImageUrl
        let metadata = seed.metadata()
        bookService.applyMetadata(metadata, to: book)

        let ideas = seed.ideas.map { $0.makeIdea(for: seed.title) }
        try bookService.saveIdeas(ideas, for: book)
        return true
    }
}
