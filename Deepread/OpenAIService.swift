import Foundation

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func extractIdeas(from text: String) async throws -> [String] {
        let prompt = """
        Extract and list all the core ideas, frameworks, and insights from the non-fiction book titled "\(text)". 
        Return them as a JSON array of strings.
        
        \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-3.5-turbo",
            messages: [
                Message(role: "system", content: "You are a helpful assistant that breaks down books into all their key ideas. Respond with a JSON array of short, standalone idea strings."),
                Message(role: "user", content: prompt)
            ],
            max_tokens: 500,
            temperature: 0.3
        )
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            throw OpenAIServiceError.noResponse
        }
        
        print("🧠 Raw OpenAI content:", content)
        
        guard let data = content.data(using: .utf8) else {
            throw OpenAIServiceError.noResponse
        }
        
        let ideas = try JSONDecoder().decode([String].self, from: data)
        return ideas
    }
}

// MARK: - Models
struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let max_tokens: Int
    let temperature: Double
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

enum OpenAIServiceError: Error {
    case noResponse
    case invalidAPIKey
    case networkError
} 