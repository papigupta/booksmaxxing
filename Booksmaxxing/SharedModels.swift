import Foundation

// MARK: - Shared OpenAI Models

struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let max_tokens: Int
    let temperature: Double
    let top_p: Double? // Optional to keep existing calls unchanged
}

struct Message: Codable {
    let role: String
    let content: String
}

struct ChatResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

// MARK: - Shared Error Types

enum OpenAIServiceError: Error {
    case noResponse
    case invalidResponse
    case invalidURL
    case invalidData
    case networkError(Error)
    case decodingError(Error)
}

enum EvaluationError: Error {
    case invalidResponse
    case decodingError(Error)
    case noResponse
    case invalidEvaluationFormat(Error)
    case networkError(Error)
    case timeout
    case rateLimitExceeded
    case serverError(Int)
}

enum BookServiceError: Error {
    case invalidRelationship
    case dataCorruption
    case saveFailed(Error)
} 
