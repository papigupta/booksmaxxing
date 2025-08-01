import Foundation
import SwiftData

@MainActor
class UserResponseService: ObservableObject {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Save User Response with Evaluation
    func saveUserResponse(
        ideaId: String,
        level: Int,
        prompt: String,
        response: String,
        evaluation: EvaluationResult,
        silverBullet: String? = nil
    ) throws -> UserResponse {
        print("DEBUG: Saving user response for idea: \(ideaId), level: \(level)")
        
        // Create new user response
        let userResponse = UserResponse(ideaId: ideaId, level: level, prompt: prompt, response: response)
        
        // Save evaluation data
        try userResponse.saveEvaluation(evaluation, silverBullet: silverBullet)
        
        // Find the idea and add the response
        if let idea = try findIdea(ideaId: ideaId) {
            idea.responses.append(userResponse)
            userResponse.idea = idea
            
            // Update idea's last practiced date
            idea.lastPracticed = Date()
            idea.currentLevel = level
        }
        
        // Save progress
        let newMasteryLevel = Progress.calculateMasteryLevel(score: evaluation.score10, currentLevel: level)
        let progress = Progress(ideaId: ideaId, level: level, score: evaluation.score10, masteryLevel: newMasteryLevel)
        
        if let idea = try findIdea(ideaId: ideaId) {
            idea.progress.append(progress)
            progress.idea = idea
            
            // Update idea's mastery level if this is the highest level completed
            if level > idea.masteryLevel {
                idea.masteryLevel = newMasteryLevel
            }
        }
        
        try modelContext.save()
        print("DEBUG: Successfully saved user response and progress")
        
        return userResponse
    }
    
    // MARK: - Get User Responses for an Idea
    func getUserResponses(for ideaId: String) throws -> [UserResponse] {
        let descriptor = FetchDescriptor<UserResponse>(
            predicate: #Predicate<UserResponse> { response in
                response.ideaId == ideaId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Get Progress for an Idea
    func getProgress(for ideaId: String) throws -> [Progress] {
        let descriptor = FetchDescriptor<Progress>(
            predicate: #Predicate<Progress> { progress in
                progress.ideaId == ideaId
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Get Latest Response for an Idea and Level
    func getLatestResponse(for ideaId: String, level: Int) throws -> UserResponse? {
        var descriptor = FetchDescriptor<UserResponse>(
            predicate: #Predicate<UserResponse> { response in
                response.ideaId == ideaId && response.level == level
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        let responses = try modelContext.fetch(descriptor)
        return responses.first
    }
    
    // MARK: - Get Best Score for an Idea and Level
    func getBestScore(for ideaId: String, level: Int) throws -> Int? {
        let responses = try getUserResponses(for: ideaId)
        let levelResponses = responses.filter { $0.level == level && $0.hasEvaluation }
        
        return levelResponses.compactMap { $0.score }.max()
    }
    
    // MARK: - Check if Level is Completed
    func isLevelCompleted(for ideaId: String, level: Int) throws -> Bool {
        let progress = try getProgress(for: ideaId)
        return progress.contains { $0.level == level && $0.isCompleted }
    }
    
    // MARK: - Get Overall Progress for an Idea
    func getOverallProgress(for ideaId: String) throws -> (completedLevels: Int, totalLevels: Int, averageScore: Double) {
        let progress = try getProgress(for: ideaId)
        let completedLevels = progress.filter { $0.isCompleted }.count
        let totalLevels = 3 // Assuming 3 levels per idea
        
        let scores = progress.compactMap { $0.score }
        let averageScore = scores.isEmpty ? 0.0 : Double(scores.reduce(0, +)) / Double(scores.count)
        
        return (completedLevels, totalLevels, averageScore)
    }
    
    // MARK: - Get Responses Grouped by Level
    func getResponsesGroupedByLevel(for ideaId: String) throws -> [Int: [UserResponse]] {
        let responses = try getUserResponses(for: ideaId)
        
        // Group responses by level
        var groupedResponses: [Int: [UserResponse]] = [:]
        for response in responses {
            if groupedResponses[response.level] == nil {
                groupedResponses[response.level] = []
            }
            groupedResponses[response.level]?.append(response)
        }
        
        return groupedResponses
    }
    
    // MARK: - Get Best Response for Each Level
    func getBestResponsesByLevel(for ideaId: String) async throws -> [Int: UserResponse] {
        let groupedResponses = try getResponsesGroupedByLevel(for: ideaId)
        var bestResponses: [Int: UserResponse] = [:]
        
        for (level, responses) in groupedResponses {
            // Find the response with the highest score
            let bestResponse = responses.max { first, second in
                let firstScore = first.score ?? 0
                let secondScore = second.score ?? 0
                return firstScore < secondScore
            }
            
            if let best = bestResponse {
                bestResponses[level] = best
            }
        }
        
        return bestResponses
    }
    
    // MARK: - Get All Responses for a Specific Level
    func getAllResponsesForLevel(ideaId: String, level: Int) async throws -> [UserResponse] {
        let responses = try getUserResponses(for: ideaId)
        return responses.filter { $0.level == level }.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Helper Methods
    private func findIdea(ideaId: String) throws -> Idea? {
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.id == ideaId
            }
        )
        
        let ideas = try modelContext.fetch(descriptor)
        return ideas.first
    }
    
    // MARK: - Debug Methods
    func getAllUserResponses() throws -> [UserResponse] {
        let descriptor = FetchDescriptor<UserResponse>()
        return try modelContext.fetch(descriptor)
    }
    
    func getAllProgress() throws -> [Progress] {
        let descriptor = FetchDescriptor<Progress>()
        return try modelContext.fetch(descriptor)
    }
    
    func clearAllUserData() throws {
        print("DEBUG: Clearing all user response and progress data")
        
        // Delete all user responses
        let responseDescriptor = FetchDescriptor<UserResponse>()
        let responses = try modelContext.fetch(responseDescriptor)
        for response in responses {
            modelContext.delete(response)
        }
        
        // Delete all progress
        let progressDescriptor = FetchDescriptor<Progress>()
        let progress = try modelContext.fetch(progressDescriptor)
        for prog in progress {
            modelContext.delete(prog)
        }
        
        try modelContext.save()
        print("DEBUG: All user data cleared")
    }
} 