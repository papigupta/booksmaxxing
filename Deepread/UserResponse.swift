import Foundation
import SwiftData

// MARK: - Flexible Evaluation Data Structure
struct EvaluationData: Codable {
    let score: Int
    let level: String
    let strengths: [String]
    let improvements: [String]
    let silverBullet: String?
    let metadata: [String: String]
    let version: String
    
    init(from evaluation: EvaluationResult, silverBullet: String? = nil) {
        self.score = evaluation.score10
        self.level = evaluation.level
        self.strengths = evaluation.strengths
        self.improvements = evaluation.improvements
        self.silverBullet = silverBullet
        self.metadata = [:]
        self.version = "1.0"
    }
    
    init(score: Int, level: String, strengths: [String], improvements: [String], silverBullet: String?, metadata: [String: String], version: String) {
        self.score = score
        self.level = level
        self.strengths = strengths
        self.improvements = improvements
        self.silverBullet = silverBullet
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
    var score: Int? {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return nil
        }
        return evaluation.score
    }
    
    var strengths: [String] {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return []
        }
        return evaluation.strengths
    }
    
    var improvements: [String] {
        guard let data = evaluationData,
              let evaluation = try? JSONDecoder().decode(EvaluationData.self, from: data) else {
            return []
        }
        return evaluation.improvements
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
            score: evaluation.score,
            level: evaluation.level,
            strengths: evaluation.strengths,
            improvements: evaluation.improvements,
            silverBullet: silverBullet,
            metadata: evaluation.metadata,
            version: evaluation.version
        )
        
        self.evaluationData = try JSONEncoder().encode(updatedEvaluation)
    }
} 