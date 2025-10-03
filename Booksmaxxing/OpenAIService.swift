import Foundation
import Network
import OSLog

// MARK: - Network Monitor

class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private let logger = Logger(subsystem: "com.booksmaxxing.app", category: "Network")
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.logger.debug("Network status changed - Connected: \(path.status == .satisfied)")
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
    private let logger = Logger(subsystem: "com.booksmaxxing.app", category: "OpenAI")
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    private let networkMonitor: NetworkMonitor
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.networkMonitor = NetworkMonitor()
        
        // Create a custom configuration with maximum reliability settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90.0  // 90 seconds for request timeout (very generous for OEQ)
        configuration.timeoutIntervalForResource = 180.0 // 180 seconds for resource timeout (3 minutes total)
        configuration.waitsForConnectivity = true       // Wait for connectivity if offline
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData // Always get fresh data
        configuration.allowsConstrainedNetworkAccess = true // Allow on limited networks
        configuration.allowsExpensiveNetworkAccess = true   // Allow on cellular
        // Allow limited parallelism when enabled for faster multi-batch requests
        configuration.httpMaximumConnectionsPerHost = DebugFlags.enableParallelOpenAI ? 3 : 1
        
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
            temperature: 0.1,
            top_p: nil
        )
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        logger.debug("Making OpenAI API request for book info extraction: '\(input)'")
        
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
        
        logger.debug("Raw LLM response for book info: \(content)")
        logger.debug("Parsed book info - Title: '\(bookInfoResponse.title)', Author: \(bookInfoResponse.author ?? "nil")")
        
        return bookInfo
    }
    
    private func extractJSONFromResponse(_ response: String) -> String {
        return SharedUtils.extractJSONObjectString(response)
    }
    
    func extractIdeas(from text: String, author: String? = nil, metadata: BookMetadata? = nil) async throws -> [String] {
        return try await withRetry(maxAttempts: 3) {
            try await self.performExtractIdeas(from: text, author: author, metadata: metadata)
        }
    }

    private func performExtractIdeas(from text: String, author: String? = nil, metadata: BookMetadata? = nil) async throws -> [String] {
        let authorContext = author.map { " by \($0)" } ?? ""
        let metadataContext: String = {
            guard let metadata = metadata else { return "" }
            var lines: [String] = []
            if let subtitle = metadata.subtitle, !subtitle.isEmpty {
                lines.append("Subtitle: \(subtitle)")
            }
            if !metadata.authors.isEmpty {
                lines.append("Authors: \(metadata.authors.joined(separator: ", "))")
            }
            if let publisher = metadata.publisher, !publisher.isEmpty {
                lines.append("Publisher: \(publisher)")
            }
            if let publishedDate = metadata.publishedDate, !publishedDate.isEmpty {
                lines.append("Published: \(publishedDate)")
            }
            if !metadata.categories.isEmpty {
                lines.append("Categories: \(metadata.categories.joined(separator: ", "))")
            }
            if let description = metadata.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                let clipped = description.count > 600 ? String(description.prefix(600)) + "…" : description
                lines.append("Synopsis: \(clipped)")
            }
            if lines.isEmpty { return "" }
            return "\n\nAdditional metadata to inform your extraction:\n" + lines.joined(separator: "\n")
        }()
        let prompt = """
        Extract the core, teachable ideas from the non-fiction book titled "\(text)"\(authorContext).
        Return them as a JSON array of strings.

        \(text)\(metadataContext)
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
            • For each idea: Use format "iX | Title — Description | Importance" where:
              - Title: short and clear, 1 line max
              - Description: 1-2 sentences explaining essence, significance, and application  
              - Importance: "Foundation" (enables understanding of most other concepts), "Building Block" (important, connects to several others), or "Enhancement" (valuable but specialized)

            Additional rules for this API call:
            • Titles must be unique. Do not output synonyms or sub-variants as separate items.  
            • Prepend each concept with an ID in the form **i1, i2, …** so the client can parse it.  

            Example output element: "i1 | Anchoring Effect — Initial numbers bias judgments even if irrelevant, leading to flawed decisions in negotiations or estimates. | Foundation"
            

            Return a **JSON array of strings** (no objects, no extra text).
        """

        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: prompt)
            ],
            max_tokens: 2000,
            temperature: 0.1,
            top_p: nil
        )
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        logger.debug("Making OpenAI API request for idea extraction: '\(text)'")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Network error during API request: \(String(describing: error))")
            throw OpenAIServiceError.networkError(error)
        }
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid HTTP response")
            throw OpenAIServiceError.invalidResponse
        }

        logger.debug("HTTP response status: \(httpResponse.statusCode, privacy: .public)")

        guard httpResponse.statusCode == 200 else {
            logger.error("HTTP error status: \(httpResponse.statusCode, privacy: .public)")
            throw OpenAIServiceError.invalidResponse
        }
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            logger.error("Failed to decode chat response: \(String(describing: error))")
            throw OpenAIServiceError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            logger.error("No content in chat response")
            throw OpenAIServiceError.noResponse
        }
        
        #if DEBUG
        logger.debug("Raw OpenAI content received")
        #endif
        
        guard let contentData = content.data(using: .utf8) else {
            logger.error("Failed to convert content to data")
            throw OpenAIServiceError.invalidData
        }
        
        do {
            let ideas = try JSONDecoder().decode([String].self, from: contentData)
            logger.debug("Successfully decoded \(ideas.count) ideas from OpenAI")
            return ideas
        } catch {
            logger.error("Failed to decode ideas array: \(String(describing: error))")
            throw OpenAIServiceError.decodingError(error)
        }
    }
    
    // Retry logic with exponential backoff and network connectivity checks
    private func withRetry<T>(maxAttempts: Int, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            // Check network connectivity before attempting
            if !networkMonitor.isConnected {
                // Wait a bit for network to come back
                logger.debug("Network offline, waiting for connectivity…")
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Check again
                if !networkMonitor.isConnected {
                    let error = OpenAIServiceError.networkError(NSError(domain: "OpenAIService", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection available"]))
                    logger.debug("Still no network connectivity on attempt \(attempt)")
                    lastError = error
                    
                    if attempt < maxAttempts {
                        continue // Try again
                    } else {
                        throw error
                    }
                }
            }
            
            do {
                self.logger.debug("Attempting API call (attempt \(attempt) of \(maxAttempts))")
                let result = try await operation()
                self.logger.debug("API call successful on attempt \(attempt)")
                return result
            } catch let error as NSError {
                lastError = error
                self.logger.debug("Attempt \(attempt) failed with error: \(error.localizedDescription)")
                self.logger.debug("Error code: \(error.code), domain: \(error.domain)")
                
                // Check for specific network errors
                let isNetworkError = error.domain == NSURLErrorDomain && (
                    error.code == NSURLErrorTimedOut ||
                    error.code == NSURLErrorCannotFindHost ||
                    error.code == NSURLErrorCannotConnectToHost ||
                    error.code == NSURLErrorNetworkConnectionLost ||
                    error.code == NSURLErrorNotConnectedToInternet ||
                    error.code == NSURLErrorDNSLookupFailed
                )
                
                if attempt < maxAttempts {
                    let baseDelay = isNetworkError ? 4.0 : 3.0
                    let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1)) // True exponential: 4s, 8s, 16s, 32s
                    let jitter = Double.random(in: 0.5...1.5) // Add jitter to prevent thundering herd
                    let delay = exponentialDelay * jitter
                    self.logger.debug("Retrying in \(String(format: "%.1f", delay)) seconds (attempt \(attempt + 1)/\(maxAttempts))…")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    self.logger.error("Max attempts reached, failing with error: \(String(describing: error))")
                }
            } catch {
                lastError = error
                self.logger.error("Attempt \(attempt) failed: \(String(describing: error))")
                
                if attempt < maxAttempts {
                    let exponentialDelay = 3.0 * pow(2.0, Double(attempt - 1)) // 3s, 6s, 12s, 24s
                    let jitter = Double.random(in: 0.5...1.5)
                    let delay = exponentialDelay * jitter
                    self.logger.debug("Retrying in \(String(format: "%.1f", delay)) seconds (attempt \(attempt + 1)/\(maxAttempts))…")
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
            temperature: 0.7,
            top_p: nil
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
            logger.error("Network error in performComplete: \(String(describing: error))")
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
        case 1:
            return "Level 1 - Why Care: Help users understand why this idea matters and its significance."
        case 2:
            return "Level 2 - When Use: Guide users to identify when to recall and apply this idea in real situations."
        case 3:
            return "Level 3 - How Wield: Encourage users to use the idea creatively or critically to extend their thinking."
        default:
            return "Level \(level) - Deep Dive: Create prompts that encourage deep, structured thinking about the idea."
        }
    }
    
    // Static templates (no AI needed)
    private func getPromptTemplate(for level: Int, idea: String) -> String? {
        // All levels now use AI generation - no static templates
        return nil
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
    
    // MARK: - Complete Method for Evaluation Service
    
    func complete(
        prompt: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double? = nil
    ) async throws -> String {
        return try await withRetry(maxAttempts: 5) {
            try await self.performComplete(
                prompt: prompt,
                model: model,
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP
            )
        }
    }
    
    private func performComplete(
        prompt: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double?
    ) async throws -> String {
        let requestBody = ChatRequest(
            model: model,
            messages: [
                Message(role: "user", content: prompt)
            ],
            max_tokens: maxTokens,
            temperature: temperature,
            top_p: topP
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
            logger.error("Network error in performComplete: \(String(describing: error))")
            throw OpenAIServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIServiceError.invalidResponse
        }
        
        let chatResponse = try validateAPIResponse(data)
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noResponse
        }
        
        return content
    }

    // MARK: - General Chat Method (with system + user messages)
    func chat(systemPrompt: String?, userPrompt: String, model: String, temperature: Double, maxTokens: Int, topP: Double? = nil) async throws -> String {
        return try await withRetry(maxAttempts: 5) {
            try await self.performChat(systemPrompt: systemPrompt, userPrompt: userPrompt, model: model, temperature: temperature, maxTokens: maxTokens, topP: topP)
        }
    }

    private func performChat(systemPrompt: String?, userPrompt: String, model: String, temperature: Double, maxTokens: Int, topP: Double?) async throws -> String {
        var messages: [Message] = []
        if let system = systemPrompt { messages.append(Message(role: "system", content: system)) }
        messages.append(Message(role: "user", content: userPrompt))

        let requestBody = ChatRequest(
            model: model,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature,
            top_p: topP
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
        do { (data, response) = try await session.data(for: request) }
        catch {
            logger.error("Network error in performChat: \(String(describing: error))")
            throw OpenAIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIServiceError.invalidResponse
        }

        let chatResponse = try validateAPIResponse(data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noResponse
        }
        return content
    }
}
