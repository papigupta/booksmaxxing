import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var bookNumber: Int  // NEW: Sequential book number (1, 2, 3...)
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var ideas: [Idea]
    var lastAccessed: Date
    
    // Google Books metadata
    var googleBooksId: String?
    var subtitle: String?
    var publisher: String?
    var language: String?
    var categories: String?  // Store as comma-separated string
    var thumbnailUrl: String?
    var coverImageUrl: String?
    var averageRating: Double?
    var ratingsCount: Int?
    var previewLink: String?
    var infoLink: String?

    init(title: String, author: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.bookNumber = 0  // Will be set by BookService
        self.createdAt = createdAt
        self.lastAccessed = createdAt
        self.ideas = []
    }
}
