import Foundation
import SwiftData

@Model
final class Primer {
    var id: UUID = UUID()
    var ideaId: String = ""  // Now uses book-specific IDs like "b1i1", "b2i3"
    
    // New Encoding Card structure fields
    var shift: String = ""
    var anchor: String = ""
    var anchorIsAuthorMetaphor: Bool = false
    var mechanismData: Data = Data()
    var lensSee: String = ""
    var lensSeeWhy: String = ""
    var lensFeel: String = ""
    var lensFeelWhy: String = ""
    var rabbitHoleData: Data = Data()
    
    // Legacy structure fields
    var thesis: String = ""
    var story: String = ""  // Default value for backward compatibility
    var examplesData: Data = Data()
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
    var examples: [String] {
        get { (try? JSONDecoder().decode([String].self, from: examplesData)) ?? [] }
        set { examplesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

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
    
    var mechanism: [String] {
        get { (try? JSONDecoder().decode([String].self, from: mechanismData)) ?? [] }
        set { mechanismData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    
    var keyNuances: [String] {
        get { (try? JSONDecoder().decode([String].self, from: keyNuancesData)) ?? [] }
        set { keyNuancesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    
    var rabbitHole: [RabbitHoleItem] {
        get { (try? JSONDecoder().decode([RabbitHoleItem].self, from: rabbitHoleData)) ?? [] }
        set { rabbitHoleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        ideaId: String,
        shift: String,
        anchor: String,
        anchorIsAuthorMetaphor: Bool,
        mechanism: [String],
        lensSee: String,
        lensSeeWhy: String,
        lensFeel: String,
        lensFeelWhy: String,
        rabbitHole: [RabbitHoleItem],
        thesis: String = "",
        story: String = "",
        examples: [String] = [],
        useItWhen: [String] = [],
        howToApply: [String] = [],
        edgesAndLimits: [String] = [],
        oneLineRecall: String = "",
        furtherLearning: [PrimerLink] = []
    ) {
        self.id = UUID()
        self.ideaId = ideaId
        self.shift = shift
        self.anchor = anchor
        self.anchorIsAuthorMetaphor = anchorIsAuthorMetaphor
        self.mechanism = mechanism
        self.lensSee = lensSee
        self.lensSeeWhy = lensSeeWhy
        self.lensFeel = lensFeel
        self.lensFeelWhy = lensFeelWhy
        self.rabbitHole = rabbitHole
        self.thesis = thesis
        self.story = story
        self.examples = examples
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
        self.shift = overview.components(separatedBy: ".").first ?? overview
        self.anchor = ""
        self.anchorIsAuthorMetaphor = false
        self.mechanism = []
        self.lensSee = ""
        self.lensSeeWhy = ""
        self.lensFeel = ""
        self.lensFeelWhy = ""
        self.rabbitHole = []
        self.keyNuances = keyNuances
        self.digDeeperLinks = digDeeperLinks
        
        // Map to new structure
        self.thesis = overview.components(separatedBy: ".").first ?? overview
        self.story = ""
        self.examples = []
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

enum RabbitHoleLabel: String, Codable {
    case debate
    case visual
    case counter
    case other
    
    var displayName: String {
        switch self {
        case .debate: return "Debate"
        case .visual: return "Visual"
        case .counter: return "Counter"
        case .other: return "Explore"
        }
    }
}

struct RabbitHoleItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var label: RabbitHoleLabel = .other
    var query: String = ""
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
