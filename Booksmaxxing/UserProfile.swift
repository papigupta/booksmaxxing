import Foundation
import SwiftData

@Model
final class UserProfile {
    // Provide default values at declaration for CloudKit compatibility
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var starterLibraryVersion: Int = 0
    var hasCompletedInitialBookSelection: Bool = false
    var lastOpenedBookTitle: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        starterLibraryVersion: Int = 0,
        hasCompletedInitialBookSelection: Bool = false,
        lastOpenedBookTitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.starterLibraryVersion = starterLibraryVersion
        self.hasCompletedInitialBookSelection = hasCompletedInitialBookSelection
        self.lastOpenedBookTitle = lastOpenedBookTitle
    }
}
