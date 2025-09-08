import Foundation
import SwiftData

@Model
final class Primer {
    var id: UUID
    var ideaId: String  // Now uses book-specific IDs like "b1i1", "b2i3"
    
    // New structure fields
    var thesis: String
    var story: String = ""  // Default value for backward compatibility
     var useItWhen: [String]
    var howToApply: [String]
    var edgesAndLimits: [String]
    var oneLineRecall: String
    var furtherLearning: [PrimerLink]
    
    // Legacy fields for backward compatibility (deprecated)
    var overview: String
    var keyNuances: [String]
    var digDeeperLinks: [PrimerLink]
    
    var createdAt: Date
    var lastAccessed: Date?
    
    // Relationship back to Idea
    @Relationship(deleteRule: .cascade) var idea: Idea?
    
    init(ideaId: String, thesis: String, story: String, useItWhen: [String], howToApply: [String], edgesAndLimits: [String], oneLineRecall: String, furtherLearning: [PrimerLink]) {
        self.id = UUID()
        self.ideaId = ideaId
        self.thesis = thesis
        self.story = story
        self.useItWhen = useItWhen
        self.howToApply = howToApply
        self.edgesAndLimits = edgesAndLimits
        self.oneLineRecall = oneLineRecall
        self.furtherLearning = furtherLearning
        
        // Legacy fields for backward compatibility
        self.overview = thesis
        self.keyNuances = useItWhen + howToApply + edgesAndLimits
        self.digDeeperLinks = furtherLearning
        
        self.createdAt = Date()
    }
    
    // Legacy initializer for backward compatibility
    init(ideaId: String, overview: String, keyNuances: [String], digDeeperLinks: [PrimerLink]) {
        self.id = UUID()
        self.ideaId = ideaId
        self.overview = overview
        self.keyNuances = keyNuances
        self.digDeeperLinks = digDeeperLinks
        
        // Map to new structure
        self.thesis = overview.components(separatedBy: ".").first ?? overview
        self.story = ""
        self.useItWhen = Array(keyNuances.prefix(3))
        self.howToApply = Array(keyNuances.dropFirst(3).prefix(3))
        self.edgesAndLimits = Array(keyNuances.dropFirst(6))
        self.oneLineRecall = overview.components(separatedBy: ".").first ?? overview
        self.furtherLearning = digDeeperLinks
        
        self.createdAt = Date()
    }
}

// MARK: - Primer Link Model
struct PrimerLink: Codable {
    let title: String
    let url: String
} 
