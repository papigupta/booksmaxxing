import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID = UUID()
    var title: String = ""
    var author: String?
    var bookNumber: Int = 0  // NEW: Sequential book number (1, 2, 3...)
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade) var ideas: [Idea]?
    var lastAccessed: Date = Date.now
    
    // Google Books metadata
    var googleBooksId: String?
    var subtitle: String?
    var publisher: String?
    var language: String?
    var categories: String?  // Store as comma-separated string
    var publishedDate: String?
    var thumbnailUrl: String?
    var coverImageUrl: String?
    var averageRating: Double?
    var ratingsCount: Int?
    var previewLink: String?
    var infoLink: String?
    var bookDescription: String?

    init(title: String, author: String? = nil, createdAt: Date = Date.now) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.bookNumber = 0  // Will be set by BookService
        self.createdAt = createdAt
        self.lastAccessed = createdAt
        self.ideas = nil
    }
}
