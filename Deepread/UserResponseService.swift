import Foundation
import SwiftData

@MainActor
class UserResponseService: ObservableObject {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Core Methods
    
    func saveUserResponse(
        ideaId: String,
        level: Int,
        prompt: String,
        response: String
    ) async throws {
        print("DEBUG: Saving user response for idea: \(ideaId), level: \(level)")
        
        let userResponse = UserResponse(ideaId: ideaId, level: level, prompt: prompt, response: response)
        
        // Find the specific idea using the book-specific ID
        if let idea = try findIdea(ideaId: ideaId) {
            userResponse.idea = idea
            idea.responses.append(userResponse)
            print("DEBUG: Linked response to idea: \(idea.title)")
        } else {
            print("DEBUG: WARNING - Could not find idea with ID: \(ideaId)")
        }
        
        modelContext.insert(userResponse)
        try modelContext.save()
        print("DEBUG: Successfully saved user response")
    }
    
    func saveUserResponseWithEvaluation(
        ideaId: String,
        level: Int,
        prompt: String,
        response: String,
        evaluation: EvaluationResult
    ) async throws -> UserResponse {
        print("DEBUG: Saving user response with evaluation for idea: \(ideaId), level: \(level)")
        
        let userResponse = UserResponse(ideaId: ideaId, level: level, prompt: prompt, response: response)
        
        // Find the specific idea using the book-specific ID
        if let idea = try findIdea(ideaId: ideaId) {
            userResponse.idea = idea
            idea.responses.append(userResponse)
            
            // Calculate new mastery level based on star score
            let newMasteryLevel = calculateMasteryLevel(currentLevel: idea.masteryLevel, starScore: evaluation.starScore)
            idea.masteryLevel = newMasteryLevel
            
            // Create progress record (converting star to 0-10 for legacy compatibility)
            let legacyScore = convertStarToLegacyScore(starScore: evaluation.starScore)
            let progress = Progress(ideaId: ideaId, level: level, score: legacyScore, masteryLevel: newMasteryLevel)
            progress.idea = idea
            idea.progress.append(progress)
            
            print("DEBUG: Linked response and progress to idea: \(idea.title)")
        } else {
            print("DEBUG: WARNING - Could not find idea with ID: \(ideaId)")
        }
        
        // Save evaluation data
        try userResponse.saveEvaluation(evaluation)
        
        modelContext.insert(userResponse)
        try modelContext.save()
        print("DEBUG: Successfully saved user response with evaluation")
        
        return userResponse
    }
    
    // MARK: - Query Methods (Now using book-specific IDs)
    
    func getUserResponses(for ideaId: String) throws -> [UserResponse] {
        let descriptor = FetchDescriptor<UserResponse>(
            predicate: #Predicate<UserResponse> { response in
                response.ideaId == ideaId
            }
        )
        return try modelContext.fetch(descriptor)
    }
    
    func getProgress(for ideaId: String) throws -> [Progress] {
        let descriptor = FetchDescriptor<Progress>(
            predicate: #Predicate<Progress> { progress in
                progress.ideaId == ideaId
            }
        )
        return try modelContext.fetch(descriptor)
    }
    
    func getLatestResponse(for ideaId: String, level: Int) throws -> UserResponse? {
        let descriptor = FetchDescriptor<UserResponse>(
            predicate: #Predicate<UserResponse> { response in
                response.ideaId == ideaId && response.level == level
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let responses = try modelContext.fetch(descriptor)
        return responses.first
    }
    
    func getBestScore(for ideaId: String, level: Int) throws -> Int? {
        let responses = try getUserResponses(for: ideaId)
        let levelResponses = responses.filter { $0.level == level }
        return levelResponses.map { $0.starScore ?? 0 }.max()
    }
    
    func isLevelCompleted(for ideaId: String, level: Int) throws -> Bool {
        let progress = try getProgress(for: ideaId)
        return progress.contains { $0.level == level }
    }
    
    func getOverallProgress(for ideaId: String) throws -> (completedLevels: Int, totalLevels: Int, averageScore: Double) {
        let progress = try getProgress(for: ideaId)
        let completedLevels = Set(progress.map { $0.level }).count
        let totalLevels = 3 // Three levels (1-3): Why Care, When Use, How Wield
        let averageScore = progress.isEmpty ? 0.0 : Double(progress.map { $0.score }.reduce(0, +)) / Double(progress.count)
        return (completedLevels, totalLevels, averageScore)
    }
    
    func getResponsesGroupedByLevel(for ideaId: String) throws -> [Int: [UserResponse]] {
        let responses = try getUserResponses(for: ideaId)
        return Dictionary(grouping: responses) { $0.level }
    }
    
    func getBestResponsesByLevel(for ideaId: String) async throws -> [Int: UserResponse] {
        let groupedResponses = try getResponsesGroupedByLevel(for: ideaId)
        var bestResponses: [Int: UserResponse] = [:]
        
        for (level, responses) in groupedResponses {
            if let bestResponse = responses.max(by: { ($0.starScore ?? 0) < ($1.starScore ?? 0) }) {
                bestResponses[level] = bestResponse
            }
        }
        
        return bestResponses
    }
    
    func getAllResponsesForLevel(ideaId: String, level: Int) async throws -> [UserResponse] {
        let responses = try getUserResponses(for: ideaId)
        return responses.filter { $0.level == level }
    }
    
    // MARK: - Helper Methods
    
    private func findIdea(ideaId: String) throws -> Idea? {
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.id == ideaId
            }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    private func calculateMasteryLevel(currentLevel: Int, starScore: Int) -> Int {
        // Star-based mastery calculation
        switch starScore {
        case 3: return max(currentLevel, 3) // ⭐⭐⭐ Aha! Moment - Mastery
        case 2: return max(currentLevel, 2) // ⭐⭐ Solid Grasp - Intermediate
        case 1: return max(currentLevel, 1) // ⭐ Getting There - Basic
        default: return currentLevel // No improvement
        }
    }
    
    private func convertStarToLegacyScore(starScore: Int) -> Int {
        // Convert star score to legacy 0-10 scale for backward compatibility
        switch starScore {
        case 1: return 4 // ⭐ Getting There
        case 2: return 7 // ⭐⭐ Solid Grasp  
        case 3: return 9 // ⭐⭐⭐ Aha! Moment
        default: return 0
        }
    }
} 