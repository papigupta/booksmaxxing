import Foundation
import SwiftData

@Model
final class Primer {
    var id: UUID
    var ideaId: String
    var overview: String
    var keyNuances: [String]
    var digDeeperLinks: [PrimerLink]
    var createdAt: Date
    var lastAccessed: Date?
    
    // Relationship back to Idea
    @Relationship(deleteRule: .cascade) var idea: Idea?
    
    init(ideaId: String, overview: String, keyNuances: [String], digDeeperLinks: [PrimerLink]) {
        self.id = UUID()
        self.ideaId = ideaId
        self.overview = overview
        self.keyNuances = keyNuances
        self.digDeeperLinks = digDeeperLinks
        self.createdAt = Date()
    }
}

// MARK: - Primer Link Model
struct PrimerLink: Codable {
    let title: String
    let url: String
} 