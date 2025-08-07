import Foundation
import Network

// MARK: - Network Monitor

class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                print("DEBUG: Network status changed - Connected: \(path.status == .satisfied)")
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - Book Info Structure

struct BookInfo {
    let title: String
    let author: String?
}

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    private let networkMonitor: NetworkMonitor
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.networkMonitor = NetworkMonitor()
        
        // Create a custom configuration with timeout settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0  // 30 seconds for request timeout
        configuration.timeoutIntervalForResource = 60.0 // 60 seconds for resource timeout
        configuration.waitsForConnectivity = true       // Wait for connectivity if offline
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData // Always get fresh data
        
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Input Validation and Sanitization
    
    private func validateAndSanitizeInput(_ input: String) -> String {
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "'")
            .prefix(1000) // Limit length
            .description
    }
    
    private func validateAPIResponse(_ data: Data) throws -> ChatResponse {
        guard !data.isEmpty else {
            throw OpenAIServiceError.noResponse
        }
        
        do {
            let response = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard !response.choices.isEmpty else {
                throw OpenAIServiceError.noResponse
            }
            return response
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }
    }
    
    private func validateBookInfoResponse(_ response: BookInfo) -> Bool {
        guard !response.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // Validate title length
        guard response.title.count <= 200 else {
            return false
        }
        
        // Validate author if present
        if let author = response.author {
            guard !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            guard author.count <= 100 else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Author Extraction
    
    func extractBookInfo(from input: String) async throws -> BookInfo {
        let sanitizedInput = validateAndSanitizeInput(input)
        return try await withRetry(maxAttempts: 3) {
            try await self.performExtractBookInfo(from: sanitizedInput)
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
            model: "gpt-4.1-mini",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            max_tokens: 200,
            temperature: 0.1
        )
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
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
        
        let chatResponse = try validateAPIResponse(data)
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noResponse
        }
        
        // Extract JSON from response
        let jsonString = extractJSONFromResponse(content)
        
        struct BookInfoResponse: Codable {
            let title: String
            let author: String?
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OpenAIServiceError.invalidData
        }
        
        let bookInfoResponse: BookInfoResponse
        do {
            bookInfoResponse = try JSONDecoder().decode(BookInfoResponse.self, from: jsonData)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }
        
        let bookInfo = BookInfo(title: bookInfoResponse.title, author: bookInfoResponse.author)
        
        // Validate the response
        guard validateBookInfoResponse(bookInfo) else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("DEBUG: Raw LLM response for book info: \(content)")
        print("DEBUG: Parsed book info - Title: '\(bookInfoResponse.title)', Author: \(bookInfoResponse.author ?? "nil")")
        
        return bookInfo
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
        let authorContext = author.map { " by \($0)" } ?? ""
        let prompt = """
        Extract the core, teachable ideas from the non-fiction book titled "\(text)"\(authorContext). 
        Return them as a JSON array of strings.

        \(text)
        """

        let systemPrompt = """
            Your goal is to extract all core, teachable ideas that a user could master one by one to deeply understand and apply the book. Output them as a JSON array of strings.
            
            \(author.map { "Book Author: \($0)" } ?? "")

            Guidelines:

            • Ideas are distinct mental models, frameworks, distinctions, or cause-effect patterns. Make each self-contained with no overlaps.
            • Split if truly separate; combine if they form one cohesive idea (e.g., related concepts like 'Affordances and Signifiers' as one if cohesive).
            • Adapt to the book's style—e.g., extract practical steps and mindsets from applied books, or theories and models from conceptual ones.
            • Be comprehensive: Cover all ideas worth mastering, in the order they appear in the book. Aim for completeness, but if over 50, prioritize the most impactful.
            • Be consistent across runs: Prioritize the book's core narrative and key takeaways. Focus on explanatory power and applicability, not trivia or examples unless essential.
            • Avoid redundancy. For eg. Don't extract "Strange Loops" and "Strange Loops in Art and Music", instead use either of the two, and aim to teach both with one single idea.
            • For each idea: Use format "iX | Title — Description" (Title: short and clear, 1 line max; Description: 1-2 sentences explaining essence, significance, and application).

            Additional rules for this API call:
            • Titles must be unique. Do not output synonyms or sub-variants as separate items.  
            • Prepend each concept with an ID in the form **i1, i2, …** so the client can parse it.  

            Example output element: "i1 | Anchoring Effect — Initial numbers bias judgments even if irrelevant, leading to flawed decisions in negotiations or estimates."
            

            Return a **JSON array of strings** (no objects, no extra text).
        """

        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: prompt)
            ],
            max_tokens: 2000,
            temperature: 0.1
        )
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        print("DEBUG: Making OpenAI API request for idea extraction: '\(text)'")
        
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
            throw OpenAIServiceError.invalidData
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
    
    // Retry logic with exponential backoff and network connectivity checks
    private func withRetry<T>(maxAttempts: Int, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            // Check network connectivity before attempting
            guard networkMonitor.isConnected else {
                let error = OpenAIServiceError.networkError(NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No internet connection"]))
                print("DEBUG: No network connectivity, skipping attempt \(attempt)")
                throw error
            }
            
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
    
    func generatePrompt(for idea: Idea, level: Int) async throws -> String {
        // Check if we have a static template for this level
        if let template = getPromptTemplate(for: level, idea: idea.title) {
            return template
        }
        
        // For levels 1+, use AI generation with level-specific system prompts
        let systemPrompt = getSystemPrompt(for: level, idea: idea)
        
        let userPrompt = """
        Generate a prompt for the idea: "\(idea.title)"
        
        Level context: \(getLevelContext(level))
        
        Create a single, engaging prompt that will help the user think deeply about this idea.
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            max_tokens: 500,
            temperature: 0.7
        )
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
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
    private func getSystemPrompt(for level: Int, idea: Idea) -> String {
        switch level {
        case 1:
            return """
            You are an expert educational prompt generator for Level 1.
            
            CONTEXT:
            - Book: \(idea.bookTitle)
            - Author: \(idea.book?.author ?? "the author")
            - Idea: \(idea.title)
            
            TASK:
            Generate one open-ended, writing-based question for Level 1 based on this idea from \(idea.bookTitle) by \(idea.book?.author ?? "the author"): "\(idea.title)". 
            The goal is to ensure the user understands why this idea matters, such as its significance, impacts, or value in real-world contexts. Make the question concise so a user can answer it thoughtfully in under 10 minutes (e.g., 1-2 short paragraphs).
            If answered correctly and substantively, it should confirm they've met the goal. Be creative with the context to make it engaging.
            
            Return only the question text, nothing else.
            """
            
        case 2:
            return """
            You are an expert educational prompt generator for Level 2.
            
            CONTEXT:
            - Book: \(idea.bookTitle)
            - Author: \(idea.book?.author ?? "the author")
            - Idea: \(idea.title)
            
            TASK:
            Generate one open-ended, writing-based question for Level 2 based on this idea from \(idea.bookTitle) by \(idea.book?.author ?? "the author"): "\(idea.title)". 
            The goal is to ensure the user can identify when to recall and apply this idea, such as triggers, situations, or practical contexts for using it effectively. Make the question concise so a user can answer it thoughtfully in under 10 minutes (e.g., 1-2 short paragraphs).
            If answered correctly and substantively, it should confirm they've met the goal. Be creative with the context to make it engaging.
            
            Return only the prompt text, nothing else.
            """
            
        case 3:
            return """
            You are an expert educational prompt generator for Level 3.
            
            CONTEXT:
            - Book: \(idea.bookTitle)
            - Author: \(idea.book?.author ?? "the author")
            - Idea: \(idea.title)
            
            TASK:
            Generate one open-ended, writing-based question for Level 3 based on this idea from \(idea.bookTitle) by \(idea.book?.author ?? "the author"): "\(idea.title)".
            The goal is to ensure the user can wield this idea creatively or critically, such as extending it to new applications, innovating with it, or analyzing its limitations. Make the question concise so a user can answer it thoughtfully in under 10 minutes (e.g., 1-2 short paragraphs).
            If answered correctly and substantively, it should confirm they've met the goal. Be creative with the context to make it engaging.
            
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


