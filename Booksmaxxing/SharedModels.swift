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

// MARK: - Shared Responses API Models

struct ResponsesReasoning: Codable {
    let effort: String
}

struct ResponsesTextConfig: Codable {
    let verbosity: String
}

struct ResponsesInputContent: Codable {
    let type: String
    let text: String
}

struct ResponsesInputItem: Codable {
    let role: String
    let content: [ResponsesInputContent]
}

struct ResponsesRequest: Codable {
    let model: String
    let input: [ResponsesInputItem]
    let reasoning: ResponsesReasoning?
    let text: ResponsesTextConfig?
    let max_output_tokens: Int
    let temperature: Double?
    let top_p: Double?
}

struct ResponsesOutputContent: Codable {
    let text: String?
}

struct ResponsesOutputItem: Codable {
    let content: [ResponsesOutputContent]?
}

struct ResponsesResponse: Codable {
    let output_text: String?
    let output: [ResponsesOutputItem]?
}

struct OpenAIErrorEnvelope: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
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
