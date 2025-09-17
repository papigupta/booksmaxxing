import Foundation
import SwiftData

@Model
final class Primer {
    var id: UUID = UUID()
    var ideaId: String = ""  // Now uses book-specific IDs like "b1i1", "b2i3"
    
    // New structure fields
    var thesis: String = ""
    var story: String = ""  // Default value for backward compatibility
    // Data-backed arrays for CloudKit compatibility
    var useItWhenData: Data = Data()
    var howToApplyData: Data = Data()
    var edgesAndLimitsData: Data = Data()
    var oneLineRecall: String = ""
    var furtherLearning: [PrimerLink] = []
    
    // CloudKit-friendly relationship for links
    @Relationship(deleteRule: .cascade) var links: [PrimerLinkItem]?
    
    // Legacy fields for backward compatibility (deprecated)
    var overview: String = ""
    var keyNuancesData: Data = Data()
    var digDeeperLinks: [PrimerLink] = []
    
    var createdAt: Date = Date.now
    var lastAccessed: Date?
    
    // Relationship back to Idea
    @Relationship var idea: Idea?
    
    // MARK: - Computed accessors for Data-backed arrays
    var useItWhen: [String] {
        get { (try? JSONDecoder().decode([String].self, from: useItWhenData)) ?? [] }
        set { useItWhenData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    
    var howToApply: [String] {
        get { (try? JSONDecoder().decode([String].self, from: howToApplyData)) ?? [] }
        set { howToApplyData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    
    var edgesAndLimits: [String] {
        get { (try? JSONDecoder().decode([String].self, from: edgesAndLimitsData)) ?? [] }
        set { edgesAndLimitsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    
    var keyNuances: [String] {
        get { (try? JSONDecoder().decode([String].self, from: keyNuancesData)) ?? [] }
        set { keyNuancesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

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

// MARK: - CloudKit-friendly Primer Link Entity
@Model
final class PrimerLinkItem {
    var id: UUID = UUID()
    var title: String = ""
    var url: String = ""
    var createdAt: Date = Date.now
    
    // Back reference to Primer
    @Relationship(inverse: \Primer.links) var primer: Primer?
    
    init(title: String, url: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.createdAt = Date()
    }
}
