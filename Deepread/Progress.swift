import Foundation
import SwiftData

@Model
final class Progress {
    var id: UUID
    var ideaId: String
    var level: Int
    var score: Int
    var completedAt: Date
    var masteryLevel: Int
    var isCompleted: Bool
    
    // Relationship back to Idea
    @Relationship(deleteRule: .cascade) var idea: Idea?
    
    init(ideaId: String, level: Int, score: Int, masteryLevel: Int = 0) {
        self.id = UUID()
        self.ideaId = ideaId
        self.level = level
        self.score = score
        self.completedAt = Date()
        self.masteryLevel = masteryLevel
        self.isCompleted = true
    }
}

// MARK: - Progress Helper Methods
extension Progress {
    static func calculateMasteryLevel(score: Int, currentLevel: Int) -> Int {
        // Mastery level calculation based on score and level
        switch currentLevel {
        case 1: // Do level
            if score >= 8 { return 1 }
            else if score >= 6 { return 0 }
            else { return 0 }
        case 2: // Question level
            if score >= 8 { return 2 }
            else if score >= 6 { return 1 }
            else { return 0 }
        case 3: // Reinvent level
            if score >= 8 { return 3 }
            else if score >= 6 { return 2 }
            else { return 1 }
        default:
            return 0
        }
    }
    
    var levelName: String {
        switch level {
        case 1: return "Do"
        case 2: return "Question"
        case 3: return "Reinvent"
        default: return "Unknown"
        }
    }
} 