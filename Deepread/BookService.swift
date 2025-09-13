import Foundation
import SwiftData

@MainActor
class BookService: ObservableObject {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Expose modelContext for helper services that must run on MainActor
    var modelContextRef: ModelContext { modelContext }
    
    // MARK: - Helper Functions
    
    /// Generates a unique book-specific idea ID
    private func generateBookSpecificIdeaId(book: Book, originalId: String) -> String {
        // Extract idea number from original ID (e.g., "i1" -> "1")
        let ideaNumber = originalId.hasPrefix("i") ? String(originalId.dropFirst()) : originalId
        return "b\(book.bookNumber)i\(ideaNumber)"
    }
    
    /// Ensures consistent ordering of ideas by ID (b1i1, b1i2, b1i3, etc.)
    private func sortIdeasById(_ book: Book) {
        let sorted = (book.ideas ?? []).sorted { $0.id < $1.id }
        book.ideas = sorted
    }
    
    func findOrCreateBook(title: String, author: String? = nil) throws -> Book {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: Looking for book with title: '\(normalizedTitle)'")
        
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.title.localizedStandardContains(normalizedTitle)
            }
        )
        
        let existingBooks = try modelContext.fetch(descriptor)
        print("DEBUG: Found \(existingBooks.count) existing books")
        
        if let existingBook = existingBooks.first {
            print("DEBUG: Using existing book: '\(existingBook.title)' with \((existingBook.ideas ?? []).count) ideas")
            existingBook.lastAccessed = Date()
            try modelContext.save()
            return existingBook
        } else {
            print("DEBUG: Creating new book: '\(normalizedTitle)'")
            let newBook = Book(title: normalizedTitle, author: author)
            
            // Assign the next sequential book number
            newBook.bookNumber = try getNextBookNumber()
            print("DEBUG: Assigned book number \(newBook.bookNumber) to new book '\(normalizedTitle)'")
            
            modelContext.insert(newBook)
            try modelContext.save()
            
            // Fetch Google Books metadata asynchronously
            Task {
                print("DEBUG: Starting Google Books metadata fetch for new book")
                await fetchAndUpdateBookMetadata(for: newBook)
            }
            
            return newBook
        }
    }
    
    // MARK: - Google Books Integration
    
    /// Fetches metadata from Google Books API and updates the book
    func fetchAndUpdateBookMetadata(for book: Book) async {
        print("DEBUG: Fetching Google Books metadata for '\(book.title)'")
        
        // Skip if we already have Google Books metadata
        if book.googleBooksId != nil {
            print("DEBUG: Book already has Google Books metadata, skipping")
            return
        }
        
        do {
            guard let metadata = try await GoogleBooksService.shared.searchBook(
                title: book.title,
                author: book.author
            ) else {
                print("DEBUG: No Google Books results found for '\(book.title)'")
                return
            }
            
            // Update book with metadata
            await MainActor.run {
                book.googleBooksId = metadata.googleBooksId
                book.subtitle = metadata.subtitle
                book.publisher = metadata.publisher
                book.language = metadata.language
                book.categories = metadata.categories.joined(separator: ", ")
                book.thumbnailUrl = metadata.thumbnailUrl
                book.coverImageUrl = metadata.coverImageUrl
                book.averageRating = metadata.averageRating
                book.ratingsCount = metadata.ratingsCount
                book.previewLink = metadata.previewLink
                book.infoLink = metadata.infoLink
                
                // If we didn't have an author, use the one from Google Books
                if book.author == nil || book.author?.isEmpty == true {
                    book.author = metadata.authors.first
                }
                
                do {
                    try modelContext.save()
                    print("DEBUG: Successfully updated book with Google Books metadata")
                    print("DEBUG: - Cover URL: \(book.coverImageUrl ?? "none")")
                    print("DEBUG: - Thumbnail URL: \(book.thumbnailUrl ?? "none")")
                    print("DEBUG: - Rating: \(book.averageRating ?? 0) (\(book.ratingsCount ?? 0) ratings)")
                } catch {
                    print("DEBUG: Failed to save Google Books metadata: \(error)")
                }
            }
        } catch {
            print("DEBUG: Error fetching Google Books metadata: \(error)")
        }
    }
    
    /// Refreshes Google Books metadata for all books (useful for migration)
    func refreshAllBooksMetadata() async throws {
        let books = try getAllBooks()
        print("DEBUG: Refreshing metadata for \(books.count) books")
        
        for book in books {
            await fetchAndUpdateBookMetadata(for: book)
            // Add small delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("DEBUG: Finished refreshing metadata for all books")
    }
    
    // MARK: - Helper Methods
    
    /// Gets the next available book number
    private func getNextBookNumber() throws -> Int {
        var descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.bookNumber, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        let books = try modelContext.fetch(descriptor)
        let maxBookNumber = books.first?.bookNumber ?? 0
        return maxBookNumber + 1
    }
    
    func saveIdeas(_ ideas: [Idea], for book: Book) throws {
        print("DEBUG: Saving \(ideas.count) ideas for book: '\(book.title)'")
        
        // Clear existing ideas and set up new ones with proper relationships
        book.ideas = []
        
        for idea in ideas {
            // Generate book-specific ID if it's not already book-specific
            if !idea.id.hasPrefix("b") {
                idea.id = generateBookSpecificIdeaId(book: book, originalId: idea.id)
            }
            idea.book = book
            if book.ideas == nil { book.ideas = [] }
            book.ideas?.append(idea)
            modelContext.insert(idea)
        }
        
        book.lastAccessed = Date()
        
        // Validate relationships before saving
        try validateBookRelationships(book)
        
        try modelContext.save()
        print("DEBUG: Successfully saved ideas to database")
        
        // Verify the save worked
        let savedBook = try getBook(withTitle: book.title)
        if let savedBook = savedBook {
            print("DEBUG: Verification - saved book has \((savedBook.ideas ?? []).count) ideas")
        } else {
            print("DEBUG: WARNING - Could not verify saved book!")
        }
    }
    
    func getBook(withTitle title: String) throws -> Book? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: Getting book with title: '\(normalizedTitle)'")
        
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.title.localizedStandardContains(normalizedTitle)
            }
        )
        
        let books = try modelContext.fetch(descriptor)
        print("DEBUG: Found \(books.count) books matching title")
        
        if let book = books.first {
            print("DEBUG: Retrieved book: '\(book.title)' with \((book.ideas ?? []).count) ideas")
            // CRITICAL: Sort ideas by ID to maintain consistent order
            sortIdeasById(book)
            print("DEBUG: Ideas sorted by ID: \(((book.ideas ?? []).map { $0.id }))")
        } else {
            print("DEBUG: No book found with title: '\(normalizedTitle)'")
        }
        
        return books.first
    }
    
    func updateBookAuthor(title: String, author: String) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: Updating author for book: '\(normalizedTitle)' to '\(author)'")
        
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.title.localizedStandardContains(normalizedTitle)
            }
        )
        
        let books = try modelContext.fetch(descriptor)
        
        if let book = books.first {
            book.author = author
            try modelContext.save()
            print("DEBUG: Successfully updated book author in database")
        } else {
            print("DEBUG: No book found to update author")
        }
    }
    
    func updateBookDetails(oldTitle: String, newTitle: String, author: String?) throws -> Book {
        let normalizedOldTitle = oldTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNewTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("DEBUG: Updating book from '\(normalizedOldTitle)' to '\(normalizedNewTitle)' with author '\(author ?? "nil")'")
        
        // First check if a book with the old title exists
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.title.localizedStandardContains(normalizedOldTitle)
            }
        )
        
        let books = try modelContext.fetch(descriptor)
        
        if let book = books.first {
            // Update the existing book
            book.title = normalizedNewTitle
            if let author = author {
                book.author = author
            }
            book.lastAccessed = Date()
            try modelContext.save()
            print("DEBUG: Successfully updated existing book details in database")
            return book
        } else {
            // If no book found with old title, create a new one
            print("DEBUG: No book found with old title, creating new book")
            return try findOrCreateBook(title: normalizedNewTitle, author: author)
        }
    }
    
    // Debug method to list all books
    func getAllBooks() throws -> [Book] {
        let descriptor = FetchDescriptor<Book>()
        let books = try modelContext.fetch(descriptor)
        print("DEBUG: Total books in database: \(books.count)")
        for book in books {
            print("DEBUG: - '\(book.title)' with \((book.ideas ?? []).count) ideas")
        }
        return books
    }
    
    // Method to clean up duplicate books (books with 0 ideas that have a similar counterpart with ideas)
    func cleanupDuplicateBooks() throws {
        print("DEBUG: Starting duplicate book cleanup")
        let allBooks = try getAllBooks()
        var booksToDelete: [Book] = []
        
        for book in allBooks {
            // If this book has 0 ideas, check if there's another book with similar title that has ideas
            if (book.ideas ?? []).isEmpty {
                // Find potential duplicate with ideas
                let potentialDuplicates = allBooks.filter { otherBook in
                    otherBook.id != book.id && 
                    !(otherBook.ideas ?? []).isEmpty &&
                    (otherBook.title.localizedCaseInsensitiveContains(book.title) || 
                     book.title.localizedCaseInsensitiveContains(otherBook.title))
                }
                
                if !potentialDuplicates.isEmpty {
                    print("DEBUG: Found duplicate book to delete: '\(book.title)' (0 ideas) - duplicate of '\(potentialDuplicates.first!.title)' (\(((potentialDuplicates.first!.ideas ?? []).count)) ideas)")
                    booksToDelete.append(book)
                }
            }
        }
        
        // Delete the duplicate books
        for book in booksToDelete {
            modelContext.delete(book)
        }
        
        if !booksToDelete.isEmpty {
            try modelContext.save()
            print("DEBUG: Deleted \(booksToDelete.count) duplicate books")
        } else {
            print("DEBUG: No duplicate books found")
        }
    }
    
    // Debug method to clear all data (for testing and migration)
    func clearAllData() throws {
        print("DEBUG: Clearing all data from database (including new test system)")
        
        // Delete all test-related data first (to maintain referential integrity)
        let questionResponseDescriptor = FetchDescriptor<QuestionResponse>()
        let questionResponses = try modelContext.fetch(questionResponseDescriptor)
        for response in questionResponses {
            modelContext.delete(response)
        }
        
        let testAttemptDescriptor = FetchDescriptor<TestAttempt>()
        let testAttempts = try modelContext.fetch(testAttemptDescriptor)
        for attempt in testAttempts {
            modelContext.delete(attempt)
        }
        
        let questionDescriptor = FetchDescriptor<Question>()
        let questions = try modelContext.fetch(questionDescriptor)
        for question in questions {
            modelContext.delete(question)
        }
        
        let testDescriptor = FetchDescriptor<Test>()
        let tests = try modelContext.fetch(testDescriptor)
        for test in tests {
            modelContext.delete(test)
        }
        
        let testProgressDescriptor = FetchDescriptor<TestProgress>()
        let testProgresses = try modelContext.fetch(testProgressDescriptor)
        for progress in testProgresses {
            modelContext.delete(progress)
        }
        
        // Delete old progress and response data
        let progressDescriptor = FetchDescriptor<Progress>()
        let progresses = try modelContext.fetch(progressDescriptor)
        for progress in progresses {
            modelContext.delete(progress)
        }
        
        // Delete all ideas
        let ideaDescriptor = FetchDescriptor<Idea>()
        let ideas = try modelContext.fetch(ideaDescriptor)
        for idea in ideas {
            modelContext.delete(idea)
        }
        
        // Delete all books
        let bookDescriptor = FetchDescriptor<Book>()
        let books = try modelContext.fetch(bookDescriptor)
        for book in books {
            modelContext.delete(book)
        }
        
        try modelContext.save()
        print("DEBUG: All data cleared - ready for new test system")
    }
    
    // MARK: - Relationship Validation and Cleanup
    
    func validateBookRelationships(_ book: Book) throws {
        // Ensure all ideas have proper relationships
        for idea in (book.ideas ?? []) {
            guard idea.book == book else {
                throw BookServiceError.invalidRelationship
            }
        }
        
        // Validate idea relationships
        for idea in (book.ideas ?? []) {
            for progress in (idea.progress ?? []) {
                guard progress.idea == idea else {
                    throw BookServiceError.invalidRelationship
                }
            }
        }
    }
    
    func cleanupOrphanedData() throws {
        print("DEBUG: Cleaning up orphaned data")
        
        // Remove orphaned ideas
        let orphanedIdeas = try modelContext.fetch(FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.book == nil
            }
        ))
        
        for idea in orphanedIdeas {
            print("DEBUG: Deleting orphaned idea: \(idea.title)")
            modelContext.delete(idea)
        }
        
        // Remove orphaned progress
        let orphanedProgress = try modelContext.fetch(FetchDescriptor<Progress>(
            predicate: #Predicate<Progress> { progress in
                progress.idea == nil
            }
        ))
        
        for progress in orphanedProgress {
            print("DEBUG: Deleting orphaned progress for idea: \(progress.ideaId)")
            modelContext.delete(progress)
        }
        
        try modelContext.save()
        print("DEBUG: Orphaned data cleanup completed")
    }
    
    func repairBrokenRelationships() throws {
        print("DEBUG: Repairing broken relationships")
        
        // Get all books
        let books = try getAllBooks()
        
        for book in books {
            // Ensure all ideas in the book have the correct book reference
            for idea in (book.ideas ?? []) {
                if idea.book != book {
                    idea.book = book
                    print("DEBUG: Fixed book relationship for idea: \(idea.title)")
                }
            }
            
            // Validate and fix idea relationships
            for idea in (book.ideas ?? []) {
                for progress in (idea.progress ?? []) {
                    if progress.idea != idea {
                        progress.idea = idea
                        print("DEBUG: Fixed progress relationship for idea: \(idea.title)")
                    }
                }
            }
        }
        
        try modelContext.save()
        print("DEBUG: Relationship repair completed")
    }
    
    // MARK: - Migration Methods
    
    func migrateExistingDataToBookSpecificIds() async throws {
        print("DEBUG: Starting migration to book-specific IDs")
        
        let allBooks = try getAllBooks()
        
        // Step 1: Assign sequential book numbers to existing books
        print("DEBUG: Assigning book numbers to \(allBooks.count) existing books")
        for (index, book) in allBooks.enumerated() {
            if book.bookNumber == 0 {
                book.bookNumber = index + 1
                print("DEBUG: Assigned book number \(book.bookNumber) to '\(book.title)'")
            }
        }
        
        // Step 2: Migrate idea IDs to book-specific format
        for book in allBooks {
            print("DEBUG: Migrating ideas for book: \(book.title) (book #\(book.bookNumber))")
            
            for idea in (book.ideas ?? []) {
                // Only migrate if the ID is not already book-specific
                if !idea.id.hasPrefix("b") {
                    let oldId = idea.id
                    let newId = generateBookSpecificIdeaId(book: book, originalId: idea.id)
                    
                    print("DEBUG: Migrating idea \(oldId) -> \(newId)")
                    
                    // Update idea ID
                    idea.id = newId
                    
                    
                    // Update all related Progress records
                    for progress in (idea.progress ?? []) {
                        progress.ideaId = newId
                    }
                    
                    // Update all related Primer records
                    let primerDescriptor = FetchDescriptor<Primer>(
                        predicate: #Predicate<Primer> { primer in
                            primer.ideaId == oldId
                        }
                    )
                    let primers = try modelContext.fetch(primerDescriptor)
                    for primer in primers {
                        primer.ideaId = newId
                    }
                }
            }
        }
        
        try modelContext.save()
        print("DEBUG: Migration completed successfully - \(allBooks.count) books migrated")
    }
} 
