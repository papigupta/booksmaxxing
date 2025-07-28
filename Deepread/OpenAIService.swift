import Foundation

// MARK: - Book Info Structure

struct BookInfo {
    let title: String
    let author: String?
}

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
    
    // MARK: - Author Extraction
    
    func extractBookInfo(from input: String) async throws -> BookInfo {
        return try await withRetry(maxAttempts: 3) {
            try await self.performExtractBookInfo(from: input)
        }
    }
    
    private func performExtractBookInfo(from input: String) async throws -> BookInfo {
        let systemPrompt = """
        You are an expert at identifying and correcting book titles and authors from user input.
        
        TASK:
        Extract the book title and determine the correct author(s) from the user's input. You should be intelligent about both title correction and author identification:
        
        SCENARIOS:
        1. NO AUTHOR MENTIONED: If the user only provides a book title, make your best educated guess about the author based on your knowledge of the book.
        2. PARTIAL AUTHOR INFO: If the user provides partial author information (e.g., "Kahneman", "Daniel K"), find the correct full name.
        3. FULL AUTHOR NAME: If the user provides a complete, correct author name, use it as-is.
        4. MULTIPLE AUTHORS: Handle multiple authors correctly (e.g., "John Smith and Jane Doe" or "Smith & Doe")
        
        TITLE CORRECTION RULES:
        1. Correct obvious formatting issues (capitalization, punctuation, spelling)
        2. Find the most commonly recognized, complete version of the title
        3. If the user provides a partial or abbreviated title, find the full title
        4. DO NOT change to a completely different book, even if similar
        5. If the title is ambiguous or unclear, keep it as provided
        6. Use the official, published title when possible
        
        AUTHOR IDENTIFICATION RULES:
        1. When no author is provided, make your best guess based on the book title
        2. When partial author info is given, find the correct full name
        3. Handle multiple authors correctly with proper formatting
        4. Clean up formatting (remove extra spaces, proper capitalization)
        5. Handle edge cases like "by [Author]" or "[Author]'s [Book]"
        6. Be confident in your author identification - if you're not sure, return null for author
        7. DO NOT assume a different book than what the user specified
        8. If you know of a book with this title, try to identify the author even if not 100% certain
        
        EXAMPLES:
        Input: "thinking fast and slow" → Title: "Thinking, Fast and Slow", Author: "Daniel Kahneman"
        Input: "thinking fast and slow by kahneman" → Title: "Thinking, Fast and Slow", Author: "Daniel Kahneman"
        Input: "thinking fast and slow by daniel kahneman" → Title: "Thinking, Fast and Slow", Author: "Daniel Kahneman"
        Input: "the design of everyday things" → Title: "The Design of Everyday Things", Author: "Don Norman"
        Input: "freakonomics by levitt" → Title: "Freakonomics", Author: "Steven D. Levitt and Stephen J. Dubner"
        Input: "atomic habits" → Title: "Atomic Habits", Author: "James Clear"
        Input: "charlie's almanack" → Title: "Poor Charlie's Almanack", Author: "Charles T. Munger"
        Input: "alchemy" → Title: "Alchemy", Author: "Rory Sutherland" (if you know this book)
        Input: "some obscure book" → Title: "Some Obscure Book", Author: null (if you're not confident)
        
        IMPORTANT: 
        - Correct partial or abbreviated titles to their full, official versions (e.g., "Charlie's Almanack" → "Poor Charlie's Almanack")
        - Do not substitute completely different books (e.g., "Alchemy" should not become "The Alchemist")
        - If you know of a book with the given title, try to identify the author
        - Only return null for author if you truly don't know or are very uncertain
        
        Return ONLY a valid JSON object with this exact structure:
        {
          "title": "Corrected Book Title",
          "author": "Author Name" or null
        }
        """
        
        let userPrompt = """
        Extract and correct book title and determine author from: "\(input)"
        """
        
        let requestBody = ChatRequest(
            model: "gpt-3.5-turbo",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            max_tokens: 200,
            temperature: 0.1
        )
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        print("DEBUG: Making OpenAI API request for book info extraction: '\(input)'")
        
        let (data, response) = try await session.data(for: request)
        
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
        
        // Extract JSON from response
        let jsonString = extractJSONFromResponse(content)
        
        struct BookInfoResponse: Codable {
            let title: String
            let author: String?
        }
        
        let bookInfoResponse: BookInfoResponse
        do {
            bookInfoResponse = try JSONDecoder().decode(BookInfoResponse.self, from: jsonString.data(using: .utf8)!)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }
        
        print("DEBUG: Raw LLM response for book info: \(content)")
        print("DEBUG: Parsed book info - Title: '\(bookInfoResponse.title)', Author: \(bookInfoResponse.author ?? "nil")")
        
        return BookInfo(title: bookInfoResponse.title, author: bookInfoResponse.author)
    }
    
    private func extractJSONFromResponse(_ response: String) -> String {
        // Look for JSON object in the response
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        return response
    }
    
    func extractIdeas(from text: String, author: String? = nil) async throws -> [String] {
        return try await withRetry(maxAttempts: 3) {
            try await self.performExtractIdeas(from: text, author: author)
        }
    }
    
    private func performExtractIdeas(from text: String, author: String? = nil) async throws -> [String] {
        let authorContext = author != nil ? " by \(author!)" : ""
        let prompt = """
        Extract and list all the core ideas, frameworks, and insights from the non-fiction book titled "\(text)"\(authorContext). 
        Return them as a JSON array of strings.

        \(text)
        """

        let systemPrompt = """
            Your task is to extract and list the most important, teachable ideas from a non-fiction book.
            
            \(author != nil ? "Book Author: \(author!)" : "")

            Each concept = one distinct, self-contained idea. No overlaps. No vague summaries.

            Prefer explanatory power over catchy phrasing. Extract the mental models, distinctions, frameworks, and cause-effect patterns that drive the book.

            Give the concept a short, clear title (1 line max) and a brief explanation (1–2 lines).

            Focus only on the most important + teachable ideas. Do not include trivia or examples unless essential.

            Follow chapter structure. List ideas in the order they are presented in the book.

            Aim for 10–50 concepts per book, depending on richness.

            Don't quote—explain.

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
        
        print("DEBUG: Making OpenAI API request for book: '\(text)'")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("DEBUG: Network error during API request: \(error)")
            throw OpenAIServiceError.networkError(error)
        }
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            print("DEBUG: Invalid HTTP response")
            throw OpenAIServiceError.invalidResponse
        }
        
        print("DEBUG: HTTP response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("DEBUG: HTTP error status: \(httpResponse.statusCode)")
            throw OpenAIServiceError.invalidResponse
        }
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            print("DEBUG: Failed to decode chat response: \(error)")
            throw OpenAIServiceError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            print("DEBUG: No content in chat response")
            throw OpenAIServiceError.noResponse
        }
        
        #if DEBUG
        print("🧠 Raw OpenAI content:", content)
        #endif
        
        guard let contentData = content.data(using: .utf8) else {
            print("DEBUG: Failed to convert content to data")
            throw OpenAIServiceError.noResponse
        }
        
        do {
            let ideas = try JSONDecoder().decode([String].self, from: contentData)
            print("DEBUG: Successfully decoded \(ideas.count) ideas from OpenAI")
            return ideas
        } catch {
            print("DEBUG: Failed to decode ideas array: \(error)")
            throw OpenAIServiceError.decodingError(error)
        }
    }
    
    // Retry logic with exponential backoff
    private func withRetry<T>(maxAttempts: Int, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                print("DEBUG: Attempt \(attempt) failed: \(error)")
                
                if attempt < maxAttempts {
                    let delay = Double(attempt) * 2.0 // Exponential backoff: 2s, 4s, 6s
                    print("DEBUG: Retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? OpenAIServiceError.networkError(NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retry attempts exceeded"]))
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


