import Foundation
import SwiftData

@Model
final class PracticeSession {
    var id: UUID = UUID()
    var ideaId: String = ""
    var bookId: String = ""
    var type: String = "lesson_practice" // e.g., "lesson_practice", "review_practice"
    var status: String = "ready" // e.g., "ready", "in_progress", "completed", "expired"
    var configVersion: Int = 1
    var configData: Data?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Test.practiceSession) var test: Test?

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
