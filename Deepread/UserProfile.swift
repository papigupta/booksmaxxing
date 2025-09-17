import Foundation
import SwiftData

@Model
final class UserProfile {
    // Provide default values at declaration for CloudKit compatibility
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), name: String = "", createdAt: Date = Date.now, updatedAt: Date = Date.now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
