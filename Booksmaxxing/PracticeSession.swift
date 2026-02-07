import Foundation
import SwiftData

struct LessonPracticeSessionConfig: Codable {
    let reviewItemIds: [String]
}

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

extension PracticeSession {
    func setLessonPracticeReviewItemIds(_ reviewItemIds: [UUID]) {
        let stableIds = Set(reviewItemIds).map { $0.uuidString }.sorted()
        let config = LessonPracticeSessionConfig(reviewItemIds: stableIds)
        configData = try? JSONEncoder().encode(config)
    }

    func lessonPracticeReviewItemIdSet() -> Set<UUID>? {
        guard let data = configData,
              let config = try? JSONDecoder().decode(LessonPracticeSessionConfig.self, from: data) else {
            return nil
        }
        return Set(config.reviewItemIds.compactMap(UUID.init(uuidString:)))
    }
}
