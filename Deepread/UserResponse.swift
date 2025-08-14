import Foundation
import SwiftData

// MARK: - Flexible Evaluation Data Structure
struct EvaluationData: Codable {
    let starScore: Int       // 1-3 star score
    let level: String
    let silverBullet: String?
    let pass: Bool           // whether the response passes the level
    let mastery: Bool        // whether mastery is achieved
    let metadata: [String: String]
    let version: String
    
    init(from evaluation: EvaluationResult, silverBullet: String? = nil) {
        self.starScore = evaluation.starScore
        self.level = evaluation.level
        self.silverBullet = silverBullet
        self.pass = evaluation.pass
        self.mastery = evaluation.mastery
        self.metadata = [:]
        self.version = "3.0"  // Updated version - removed strengths/weaknesses
    }
    
    init(starScore: Int, level: String, silverBullet: String?, pass: Bool, mastery: Bool, metadata: [String: String], version: String) {
        self.starScore = starScore
        self.level = level
        self.silverBullet = silverBullet
        self.pass = pass
        self.mastery = mastery
        self.metadata = metadata
        self.version = version
    }
}

// MARK: - User Response Model
@Model
final class UserResponse {
    var id: UUID
    var ideaId: String
    var level: Int
    var prompt: String // Store the original prompt
    var response: String
    var timestamp: Date
    var evaluationData: Data? // JSON encoded evaluation data
    var evaluationVersion: String // Track schema version
    
    // Relationship back to Idea
    @Relationship(deleteRule: .cascade) var idea: Idea?
    
    init(ideaId: String, level: Int, prompt: String, response: String) {
        self.id = UUID()
        self.ideaId = ideaId
        self.level = level
        self.prompt = prompt
        self.response = response
        self.timestamp = Date()
        self.evaluationVersion = "1.0"
    }
}

// MARK: - Computed Properties for Easy Access
extension UserResponse {
    var starScore: Int? {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return nil
        }
        return evaluation.starScore
    }
    
    var silverBullet: String? {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return nil
        }
        return evaluation.silverBullet
    }
    
    var evaluationLevel: String? {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return nil
        }
        return evaluation.level
    }
    
    var pass: Bool? {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return nil
        }
        return evaluation.pass
    }
    
    var mastery: Bool? {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return nil
        }
        return evaluation.mastery
    }
    
    var hasEvaluation: Bool {
        return evaluationData != nil
    }
}

// MARK: - Evaluation Saving Methods
extension UserResponse {
    func saveEvaluation(_ evaluation: EvaluationResult) throws {
        let evaluationData = EvaluationData(from: evaluation)
        self.evaluationData = try JSONEncoder().encode(evaluationData)
        self.evaluationVersion = evaluationData.version
    }
    
    func saveEvaluation(_ evaluation: EvaluationResult, silverBullet: String? = nil) throws {
        let evaluationData = EvaluationData(from: evaluation, silverBullet: silverBullet)
        self.evaluationData = try JSONEncoder().encode(evaluationData)
        self.evaluationVersion = evaluationData.version
    }
    
    func updateSilverBullet(_ silverBullet: String) throws {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            throw NSError(domain: "UserResponse", code: 1, userInfo: [NSLocalizedDescriptionKey: "No evaluation data found"])
        }
        
        // Create new evaluation data with updated silver bullet
        let updatedEvaluation = EvaluationData(
            starScore: evaluation.starScore,
            level: evaluation.level,
            silverBullet: silverBullet,
            pass: evaluation.pass,
            mastery: evaluation.mastery,
            metadata: evaluation.metadata,
            version: evaluation.version
        )
        
        self.evaluationData = try JSONEncoder().encode(updatedEvaluation)
    }
} 