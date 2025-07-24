import Foundation
import SwiftData

@MainActor
class BookService: ObservableObject {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
            print("DEBUG: Using existing book: '\(existingBook.title)' with \(existingBook.ideas.count) ideas")
            existingBook.lastAccessed = Date()
            try modelContext.save()
            return existingBook
        } else {
            print("DEBUG: Creating new book: '\(normalizedTitle)'")
            let newBook = Book(title: normalizedTitle, author: author)
            modelContext.insert(newBook)
            try modelContext.save()
            return newBook
        }
    }
    
    func saveIdeas(_ ideas: [Idea], for book: Book) throws {
        print("DEBUG: Saving \(ideas.count) ideas for book: '\(book.title)'")
        
        // Clear existing ideas and set up new ones with proper relationships
        book.ideas.removeAll()
        
        for idea in ideas {
            idea.book = book
            book.ideas.append(idea)
            modelContext.insert(idea)
        }
        
        book.lastAccessed = Date()
        try modelContext.save()
        print("DEBUG: Successfully saved ideas to database")
        
        // Verify the save worked
        let savedBook = try getBook(withTitle: book.title)
        if let savedBook = savedBook {
            print("DEBUG: Verification - saved book has \(savedBook.ideas.count) ideas")
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
            print("DEBUG: Retrieved book: '\(book.title)' with \(book.ideas.count) ideas")
            // CRITICAL: Sort ideas by ID to maintain consistent order
            book.ideas.sort { idea1, idea2 in
                idea1.id < idea2.id
            }
            print("DEBUG: Ideas sorted by ID: \(book.ideas.map { $0.id })")
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
    
    // Debug method to list all books
    func getAllBooks() throws -> [Book] {
        let descriptor = FetchDescriptor<Book>()
        let books = try modelContext.fetch(descriptor)
        print("DEBUG: Total books in database: \(books.count)")
        for book in books {
            print("DEBUG: - '\(book.title)' with \(book.ideas.count) ideas")
        }
        return books
    }
    
    // Debug method to clear all data (for testing)
    func clearAllData() throws {
        print("DEBUG: Clearing all data from database")
        
        // Delete all books
        let bookDescriptor = FetchDescriptor<Book>()
        let books = try modelContext.fetch(bookDescriptor)
        for book in books {
            modelContext.delete(book)
        }
        
        // Delete all ideas
        let ideaDescriptor = FetchDescriptor<Idea>()
        let ideas = try modelContext.fetch(ideaDescriptor)
        for idea in ideas {
            modelContext.delete(idea)
        }
        
        try modelContext.save()
        print("DEBUG: All data cleared")
    }
} 