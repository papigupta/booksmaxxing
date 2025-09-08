import Foundation
import SwiftData

@Model
final class PracticeSession {
    var id: UUID
    var ideaId: String
    var bookId: String
    var type: String // e.g., "lesson_practice", "review_practice"
    var status: String // e.g., "ready", "in_progress", "completed", "expired"
    var configVersion: Int
    var configData: Data?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade) var test: Test?

    init(ideaId: String, bookId: String, type: String, status: String = "ready", configVersion: Int = 1, configData: Data? = nil) {
        self.id = UUID()
        self.ideaId = ideaId
        self.bookId = bookId
        self.type = type
        self.status = status
        self.configVersion = configVersion
        self.configData = configData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

