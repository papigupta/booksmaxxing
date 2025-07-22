import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var ideas: [Idea]
    var lastAccessed: Date

    init(title: String, author: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.createdAt = createdAt
        self.lastAccessed = createdAt
        self.ideas = []
    }
}
