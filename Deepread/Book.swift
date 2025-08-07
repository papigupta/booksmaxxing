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
