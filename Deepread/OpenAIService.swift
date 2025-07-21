import Foundation

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        // Create a custom configuration with timeout settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0  // 30 seconds for request timeout
        configuration.timeoutIntervalForResource = 60.0 // 60 seconds for resource timeout
        configuration.waitsForConnectivity = true       // Wait for connectivity if offline
        
        self.session = URLSession(configuration: configuration)
    }
    
    func extractIdeas(from text: String) async throws -> [String] {
        let prompt = """
        Extract and list all the core ideas, frameworks, and insights from the non-fiction book titled "\(text)". 
        Return them as a JSON array of strings.

        \(text)
        """


        let systemPrompt = """
            Your task is to extract and list the most important, teachable ideas from a non-fiction book.

            Each concept = one distinct, self-contained idea. No overlaps. No vague summaries.

            Prefer explanatory power over catchy phrasing. Extract the mental models, distinctions, frameworks, and cause-effect patterns that drive the book.

            Give the concept a short, clear title (1 line max) and a brief explanation (1–2 lines).

            Focus only on the most important + teachable ideas. Do not include trivia or examples unless essential.

            Ignore chapter structure. Group similar ideas under unified concepts.

            Aim for 10–50 concepts per book, depending on richness.

            Don’t quote—explain.

            Additional rules for this API call:
            • Titles must be unique. Do not output synonyms or sub-variants as separate items.  
            • Prepend each concept with an ID in the form **i1, i2, …** so the client can parse it.  
            • Assign a depth_target (1, 2, or 3) to each idea using the rubric below. Focus on how much understanding is required before the idea becomes useful or safe to use.

            Use this rubric:

            1 (Use): The idea can be applied directly with shallow understanding. It is simple, isolated, and unlikely to be misused. Learner benefit is immediate after basic explanation. Use only for small, narrow-scope ideas.

            2 (Think with): The idea requires reflection, context, or judgment to apply correctly. It is often misunderstood or used in oversimplified ways. Learners must analyze its limits or compare it to alternatives. Use for foundational ideas that are frequently misinterpreted when treated too simply.

            3 (Build with): The idea is generative. Learners should be able to extend or remix it into tools, frameworks, or systems. It serves as a building block for broader innovation. Use only when the idea clearly supports creative transfer into new domains.

            Assignment rules:
            - Do not assign 1 to any idea that serves as a core mental model, explanatory lens, or conceptual foundation for the rest of the book.
            - Use 3 only when the idea enables design, strategy, or cross-domain transfer.
            - Avoid assigning the same value to every idea. Return a realistic mix.
            
            Example output element: `"i7 | Anchoring effect — Initial numbers bias estimates even when irrelevant. | 2"`
            • If more than 25 unique concepts remain, keep only the 25 most important, then maintain narrative order.

            Return a **JSON array of strings** (no objects, no extra text).
        """

        
        let requestBody = ChatRequest(
            model: "gpt-3.5-turbo",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: prompt)
            ],
            max_tokens: 1000,
            temperature: 0.3
        )
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIServiceError.networkError(error)
        }
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OpenAIServiceError.invalidResponse
        }
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noResponse
        }
        
        #if DEBUG
        print("🧠 Raw OpenAI content:", content)
        #endif
        
        guard let contentData = content.data(using: .utf8) else {
            throw OpenAIServiceError.noResponse
        }
        
        do {
            return try JSONDecoder().decode([String].self, from: contentData)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }
    }
    
    func generatePrompt(for idea: String, level: Int) async throws -> String {
        // Check if we have a static template for this level
        if let template = getPromptTemplate(for: level, idea: idea) {
            return template
        }
        
        // For levels 1+, use AI generation with level-specific system prompts
        let systemPrompt = getSystemPrompt(for: level)
        
        let userPrompt = """
        Generate a prompt for the idea: "\(idea)"
        
        Level context: \(getLevelContext(level))
        
        Create a single, engaging prompt that will help the user think deeply about this idea.
        """
        
        let requestBody = ChatRequest(
            model: "gpt-3.5-turbo",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            max_tokens: 150,
            temperature: 0.7
        )
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIServiceError.invalidResponse
        }
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func getLevelContext(_ level: Int) -> String {
        switch level {
        case 0:
            return "Level 0 - Thought Dump: Encourage free-form, unfiltered thinking. Ask users to dump all their thoughts about the idea, no matter how messy or half-formed."
        case 1:
            return "Level 1 - Use: Help users apply the idea directly in practical situations."
        case 2:
            return "Level 2 - Think with: Guide users to use the idea as a thinking tool to analyze and solve problems."
        case 3:
            return "Level 3 - Build with: Encourage users to use the idea as a foundation to create new concepts and systems."
        default:
            return "Level \(level) - Deep Dive: Create prompts that encourage deep, structured thinking about the idea."
        }
    }
    
    // Static templates (no AI needed)
    private func getPromptTemplate(for level: Int, idea: String) -> String? {
        switch level {
        case 0:
            return "Write down everything that comes to your mind when you hear ***\(idea)***"
        default:
            return nil // Use AI generation for other levels
        }
    }
    
    // Level-specific system prompts for AI generation
    private func getSystemPrompt(for level: Int) -> String {
        switch level {
        case 1:
            return """
            You are an expert educational prompt generator for Level 1 (Use).
            
            Guidelines:
            - Create prompts that help users apply the idea directly in practical situations
            - Ask questions that encourage immediate, practical application
            - Focus on "How can I use this right now?" type questions
            - Make prompts actionable and concrete
            - Avoid yes/no questions
            - Keep prompts concise but open-ended
            
            Return only the prompt text, nothing else.
            """
            
        case 2:
            return """
            You are an expert educational prompt generator for Level 2 (Think with).
            
            Guidelines:
            - Create prompts that help users use the idea as a thinking tool
            - Ask questions that encourage analysis and problem-solving
            - Focus on "How does this help me think about..." type questions
            - Encourage using the idea as a mental model or framework
            - Avoid yes/no questions
            - Keep prompts concise but open-ended
            
            Return only the prompt text, nothing else.
            """
            
        case 3:
            return """
            You are an expert educational prompt generator for Level 3 (Build with).
            
            Guidelines:
            - Create prompts that help users build new concepts using the idea
            - Ask questions that encourage creation and innovation
            - Focus on "What can I create using this?" and "How can I combine this with..." type questions
            - Encourage synthesis and construction of new ideas
            - Avoid yes/no questions
            - Keep prompts concise but open-ended
            
            Return only the prompt text, nothing else.
            """
            
        default:
            return """
            You are an expert educational prompt generator. Your task is to create engaging, thought-provoking prompts that help users deeply engage with ideas from books.
            
            Guidelines:
            - Make prompts personal and reflective
            - Encourage free-form thinking
            - Avoid yes/no questions
            - Keep prompts concise but open-ended
            - Focus on the specific idea provided
            
            Return only the prompt text, nothing else.
            """
        }
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
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
}
