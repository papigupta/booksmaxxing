import Foundation
import SwiftData

/// Immutable concept wrapper with a book-specific ID (`b1i1`, `b2i1`, etc.).
@Model
final class Idea {
    var id: String     // e.g. "b1i1" (book1, idea1) or "b2i3" (book2, idea3)
    var title: String  // e.g. "Godel's Incompleteness Theorem"
    var ideaDescription: String  // e.g. "Mathematical systems cannot prove their own consistency."
    var bookTitle: String  // e.g. "Godel, Escher, Bach"
    var depthTarget: Int  // 1 = Do, 2 = Question, 3 = Reinvent
    var masteryLevel: Int // 0 = not started, 1 = basic, 2 = intermediate, 3 = mastered
    var lastPracticed: Date?
    var currentLevel: Int? // The exact level user was on when they left
    
    // Relationship back to Book
    @Relationship(deleteRule: .cascade) var book: Book?
    
    // Relationships to UserResponse and Progress
    @Relationship(deleteRule: .cascade) var responses: [UserResponse]
    @Relationship(deleteRule: .cascade) var progress: [Progress]
    
    init(id: String, title: String, description: String, bookTitle: String, depthTarget: Int, masteryLevel: Int = 0, lastPracticed: Date? = nil, currentLevel: Int? = nil) {
        self.id = id
        self.title = title
        self.ideaDescription = description
        self.bookTitle = bookTitle
        self.depthTarget = depthTarget
        self.masteryLevel = masteryLevel
        self.lastPracticed = lastPracticed
        self.currentLevel = currentLevel
        self.responses = []
        self.progress = []
        print("DEBUG: Created Idea with id: \(id), title: \(title), bookTitle: \(bookTitle)")
    }
    
    // MARK: - Helper Methods
    
    /// Extracts the original idea number from the book-specific ID
    var ideaNumber: String {
        // Extract the part after 'b' and before 'i' (book number) and after 'i' (idea number)
        // e.g., "b1i3" -> "3", "b2i1" -> "1"
        let components = id.split(separator: "i")
        return components.count > 1 ? String(components[1]) : id
    }
    
    /// Extracts the book number from the book-specific ID
    var bookNumber: String {
        // Extract the part between 'b' and 'i'
        // e.g., "b1i3" -> "1", "b2i1" -> "2"
        let components = id.split(separator: "i")
        if components.count > 1 {
            let bookPart = components[0]
            return bookPart.hasPrefix("b") ? String(bookPart.dropFirst()) : "1"
        }
        return "1"
    }
} 