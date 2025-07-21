import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var createdAt: Date

    init(title: String, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
    }
}
