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
    
    func findOrCreateBook(title: String, author: String? = nil, triggerMetadataFetch: Bool = true) throws -> Book {
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
            UserAnalyticsService.shared.refreshBookStats()
            
            // Keep early Google Books fetch skipped until author known (accuracy)
            if triggerMetadataFetch, let author = author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task {
                    print("DEBUG: Starting Google Books metadata fetch for new book (author known)")
                    await fetchAndUpdateBookMetadata(for: newBook)
                }
            } else {
                print("DEBUG: Skipping early Google Books fetch (author unknown)")
            }
            
            return newBook
        }
    }
    
    // MARK: - Google Books Integration
    
    /// Fetches metadata from Google Books API and updates the book
    /// Set `force` to true to refresh even if metadata already exists.
    func fetchAndUpdateBookMetadata(for book: Book, force: Bool = false) async {
        print("DEBUG: Fetching Google Books metadata for '\(book.title)'")
        
        // Skip if we already have Google Books metadata
        if !force, book.googleBooksId != nil {
            print("DEBUG: Book already has Google Books metadata, skipping (force=false)")
            return
        }
        
        do {
            guard let metadata = try await GoogleBooksService.shared.searchBook(
                title: book.title,
                author: book.author
            ) else {
                print("DEBUG: No Google Books results found for '\(book.title)'")
                if force {
                    await MainActor.run {
                        // Clear any potentially wrong early metadata when forcing refresh
                        book.googleBooksId = nil
                        book.thumbnailUrl = nil
                        book.coverImageUrl = nil
                        do { try modelContext.save() } catch { print("DEBUG: Failed to clear metadata: \(error)") }
                    }
                }
                return
            }
            
            // Update book with metadata
            await MainActor.run {
                self.applyMetadata(metadata, to: book)
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

    func applyMetadata(_ metadata: BookMetadata, to book: Book, overrideExisting: Bool = true) {
        book.googleBooksId = metadata.googleBooksId
        if overrideExisting || book.subtitle == nil { book.subtitle = metadata.subtitle }
        if overrideExisting || book.publisher == nil { book.publisher = metadata.publisher }
        if overrideExisting || book.language == nil { book.language = metadata.language }
        if overrideExisting || book.categories == nil { book.categories = metadata.categories.joined(separator: ", ") }
        if overrideExisting || book.thumbnailUrl == nil { book.thumbnailUrl = metadata.thumbnailUrl }
        if overrideExisting || book.coverImageUrl == nil { book.coverImageUrl = metadata.coverImageUrl }
        if overrideExisting || book.averageRating == nil { book.averageRating = metadata.averageRating }
        if overrideExisting || book.ratingsCount == nil { book.ratingsCount = metadata.ratingsCount }
        if overrideExisting || book.previewLink == nil { book.previewLink = metadata.previewLink }
        if overrideExisting || book.infoLink == nil { book.infoLink = metadata.infoLink }
        if overrideExisting || book.publishedDate == nil { book.publishedDate = metadata.publishedDate }
        if overrideExisting || book.bookDescription == nil { book.bookDescription = metadata.description }

        if overrideExisting || book.author == nil || book.author?.isEmpty == true {
            book.author = metadata.authors.first ?? book.author
        }

        do {
            try modelContext.save()
            print("DEBUG: Applied metadata to book '\(book.title)' (Google ID: \(metadata.googleBooksId))")
        } catch {
            print("DEBUG: Failed to save metadata application: \(error)")
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

    // MARK: - Destructive Deletion
    /// Permanently deletes a book and all associated data generated by the system or saved by the user.
    /// This includes:
    /// - Review queue items for the book
    /// - Idea coverage + missed question records
    /// - Practice sessions
    /// - Stored lessons
    /// - Book-specific theme
    /// - Legacy mastery records (IdeaMastery)
    /// - The book itself (cascades ideas, primers, tests, attempts, responses, progress, test progress)
    func deleteBookAndAllData(book: Book) throws {
        let bookId = book.id.uuidString
        let bookTitle = book.title
        let targetBookId = bookId
        let targetBookTitle = bookTitle
        let targetBookUUID = book.id
        print("⚠️ DELETION: Starting permanent delete for book '" + bookTitle + "' (id: " + bookId + ")")

        // 1) Review queue items (by bookId, and legacy by bookTitle if bookId is nil)
        do {
            let byIdDescriptor = FetchDescriptor<ReviewQueueItem>(
                predicate: #Predicate<ReviewQueueItem> { item in item.bookId == targetBookId }
            )
            let byTitleLegacyDescriptor = FetchDescriptor<ReviewQueueItem>(
                predicate: #Predicate<ReviewQueueItem> { item in item.bookId == nil }
            )
            let itemsById = try modelContext.fetch(byIdDescriptor)
            // Filter legacy by matching bookTitle in Swift to avoid predicate limitations
            let legacyCandidates = try modelContext.fetch(byTitleLegacyDescriptor)
            let legacyItems = legacyCandidates.filter { $0.bookTitle == targetBookTitle }
            (itemsById + legacyItems).forEach { modelContext.delete($0) }
            print("⚠️ DELETION: Deleted \(itemsById.count + legacyItems.count) ReviewQueueItem rows (including legacy)")
        } catch {
            print("⚠️ DELETION: Error deleting ReviewQueueItem rows: \(error)")
        }

        // 2) Idea coverage for this book (cascade removes MissedQuestionRecord)
        do {
            let covDescriptor = FetchDescriptor<IdeaCoverage>(
                predicate: #Predicate<IdeaCoverage> { c in c.bookId == targetBookId }
            )
            let coverages = try modelContext.fetch(covDescriptor)
            coverages.forEach { modelContext.delete($0) }
            print("⚠️ DELETION: Deleted \(coverages.count) IdeaCoverage rows")
        } catch {
            print("⚠️ DELETION: Error deleting IdeaCoverage: \(error)")
        }

        // 3) Practice sessions
        do {
            let sessDescriptor = FetchDescriptor<PracticeSession>(
                predicate: #Predicate<PracticeSession> { s in s.bookId == targetBookId }
            )
            let sessions = try modelContext.fetch(sessDescriptor)
            sessions.forEach { modelContext.delete($0) }
            print("⚠️ DELETION: Deleted \(sessions.count) PracticeSession rows")
        } catch {
            print("⚠️ DELETION: Error deleting PracticeSession: \(error)")
        }

        // 4) Stored lessons
        do {
            let lessonDescriptor = FetchDescriptor<StoredLesson>(
                predicate: #Predicate<StoredLesson> { l in l.bookId == targetBookId }
            )
            let lessons = try modelContext.fetch(lessonDescriptor)
            lessons.forEach { modelContext.delete($0) }
            print("⚠️ DELETION: Deleted \(lessons.count) StoredLesson rows")
        } catch {
            print("⚠️ DELETION: Error deleting StoredLesson: \(error)")
        }

        // 5) Book-specific theme
        do {
            let themeDescriptor = FetchDescriptor<BookTheme>(
                predicate: #Predicate<BookTheme> { t in t.bookId == targetBookUUID }
            )
            let themes = try modelContext.fetch(themeDescriptor)
            themes.forEach { modelContext.delete($0) }
            print("⚠️ DELETION: Deleted \(themes.count) BookTheme rows")
        } catch {
            print("⚠️ DELETION: Error deleting BookTheme: \(error)")
        }

        // 6) Legacy mastery records (IdeaMastery) if present
        do {
            let legacyDescriptor = FetchDescriptor<IdeaMastery>(
                predicate: #Predicate<IdeaMastery> { m in m.bookId == targetBookId }
            )
            let legacy = try modelContext.fetch(legacyDescriptor)
            legacy.forEach { modelContext.delete($0) }
            if !legacy.isEmpty {
                print("⚠️ DELETION: Deleted \(legacy.count) legacy IdeaMastery rows")
            }
        } catch {
            // This model may not exist in some containers — ignore errors.
        }

        // 7) Defensive manual cascade: delete all ideas and their nested entities first
        do {
            let ideas = (book.ideas ?? [])
            print("⚠️ DELETION: Manual cascade for \(ideas.count) ideas…")
            for (idx, idea) in ideas.enumerated() {
                print("⚠️ DELETION: Processing idea \(idx+1)/\(ideas.count) id=\(idea.id) title=\(idea.title)")
                // Tests graph (include any orphaned tests matched by ideaId)
                var testsToDelete: [Test] = idea.tests ?? []
                let targetIdeaId = idea.id
                let orphanDescriptor = FetchDescriptor<Test>(
                    predicate: #Predicate<Test> { t in t.ideaId == targetIdeaId }
                )
                if let orphanedTests = try? modelContext.fetch(orphanDescriptor) {
                    let existingIds = Set(testsToDelete.map { $0.id })
                    for test in orphanedTests where !existingIds.contains(test.id) {
                        testsToDelete.append(test)
                    }
                }

                for test in testsToDelete {
                    if var questions = test.questions {
                        for q in questions {
                            if let responses = q.responses { responses.forEach { resp in resp.attempt = nil; resp.question = nil; modelContext.delete(resp) } }
                            q.test = nil
                            modelContext.delete(q)
                        }
                        questions.removeAll()
                        test.questions = questions
                    }
                    if var attempts = test.attempts { attempts.forEach { at in at.test = nil; modelContext.delete(at) } ; attempts.removeAll(); test.attempts = attempts }
                    test.practiceSession = nil
                    test.idea = nil
                    modelContext.delete(test)
                }
                idea.tests = []

                // Primer graph
                if var links = idea.primer?.links { links.forEach { l in l.primer = nil; modelContext.delete(l) }; links.removeAll(); idea.primer?.links = links }
                if let primer = idea.primer { primer.idea = nil; modelContext.delete(primer); idea.primer = nil }

                // Progress
                if var progress = idea.progress { progress.forEach { p in p.idea = nil; modelContext.delete(p) }; progress.removeAll(); idea.progress = progress }
                if var tps = idea.testProgresses { tps.forEach { tp in tp.idea = nil; modelContext.delete(tp) }; tps.removeAll(); idea.testProgresses = tps }

                // Detach from book then delete
                idea.book = nil
                modelContext.delete(idea)

                if (idx % 10) == 9 { try? modelContext.save() }
            }
            try modelContext.save()
            print("⚠️ DELETION: Manual cascade completed and saved")
        } catch {
            print("⚠️ DELETION: Error during manual cascade delete: \(error)")
        }

        // 8) Finally delete the book itself
        print("⚠️ DELETION: Deleting Book object…")
        book.ideas = []
        modelContext.delete(book)
        try modelContext.save()
        print("⚠️ DELETION: Completed deletion for book '" + bookTitle + "'")
        UserAnalyticsService.shared.refreshBookStats()
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
