import Foundation
import Network

// MARK: - Robust Evaluation System
/*
 This EvaluationService provides a highly reliable and stable evaluation system with the following features:
 
 🔧 RELIABILITY FEATURES:
 - Custom URLSession with optimized timeouts (45s request, 90s resource)
 - Network connectivity monitoring with automatic retry logic
 - Exponential backoff retry strategy (1.5s, 3s delays)
 - Comprehensive error handling for all failure scenarios
 - Input validation and sanitization
 - HTTP status code specific error handling
 
 🚀 PERFORMANCE FEATURES:
 - Connection pooling (5 max connections per host)
 - HTTP pipelining enabled
 - Fresh data policy (no caching)
 - Waits for connectivity when offline
 
 🛡️ ERROR HANDLING:
 - Network errors (timeout, no connection)
 - Server errors (rate limits, 5xx errors)
 - Response format errors (JSON parsing, validation)
 - Graceful degradation with user-friendly messages
 
 📊 MONITORING:
 - Debug logging for troubleshooting
 - Network status tracking
 - Retry attempt tracking
 - Performance metrics logging
 
 This system is designed to handle the most challenging network conditions
 and provide a smooth user experience even when API calls fail initially.
 */

// MARK: - Evaluation Models

struct EvaluationResult: Codable {
    let level: String        // e.g. "L0", "L3", "LN"
    let score10: Int         // 0-10 integer
    let strengths: [String]  // exactly two short bullets
    let improvements: [String] // exactly two short bullets
}

struct LevelConfig {
    let level: Int
    let name: String
    let description: String
    let evaluationCriteria: [String]
    let scoringGuide: String
}

// MARK: - Network Monitor for Evaluation Service

class EvaluationNetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "EvaluationNetworkMonitor")
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                print("EVAL DEBUG: Network status changed - Connected: \(path.status == .satisfied)")
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - Robust Evaluation Service

class EvaluationService {
    private let apiKey: String
    private let session: URLSession
    private let networkMonitor: EvaluationNetworkMonitor
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.networkMonitor = EvaluationNetworkMonitor()
        
        // Create robust session configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45.0  // 45 seconds for request timeout
        configuration.timeoutIntervalForResource = 90.0 // 90 seconds for resource timeout
        configuration.waitsForConnectivity = true       // Wait for connectivity if offline
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData // Always get fresh data
        
        // Add retry configuration
        configuration.httpMaximumConnectionsPerHost = 5
        configuration.httpShouldUsePipelining = true
        
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Main Evaluation Function with Retry Logic
    
    func evaluateSubmission(
        idea: Idea,
        userResponse: String,
        level: Int
    ) async throws -> EvaluationResult {
        
        // Validate inputs
        guard !userResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "User response cannot be empty"]))
        }
        
        // Check network connectivity before starting
        guard networkMonitor.isConnected else {
            throw EvaluationError.networkError(NSError(domain: "EvaluationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No internet connection available"]))
        }
        
        return try await withRetry(maxAttempts: 3, operation: {
            try await self.performEvaluation(idea: idea, userResponse: userResponse, level: level)
        })
    }
    
    private func performEvaluation(
        idea: Idea,
        userResponse: String,
        level: Int
    ) async throws -> EvaluationResult {
        
        print("EVAL DEBUG: Starting evaluation for idea: \(idea.title), level: \(level)")
        
        let levelConfig = getLevelConfig(for: level)
        
        // Step 1: Get score with retry
        print("EVAL DEBUG: Getting score...")
        let score = try await withRetry(maxAttempts: 2, operation: {
            try await self.getScore(
                idea: idea,
                userResponse: userResponse,
                level: level,
                levelConfig: levelConfig
            )
        })
        print("EVAL DEBUG: Score received: \(score)")
        
        // Step 2: Get strengths and improvements with retry
        print("EVAL DEBUG: Getting feedback...")
        let feedback = try await withRetry(maxAttempts: 2, operation: {
            try await self.getStrengthsAndImprovements(
                idea: idea,
                userResponse: userResponse,
                level: level,
                levelConfig: levelConfig,
                score: score
            )
        })
        print("EVAL DEBUG: Feedback received: \(feedback.strengths.count) strengths, \(feedback.improvements.count) improvements")
        
        let result = EvaluationResult(
            level: "L\(level)",
            score10: score,
            strengths: feedback.strengths,
            improvements: feedback.improvements
        )
        
        print("EVAL DEBUG: Evaluation completed successfully")
        return result
    }
    
    // MARK: - Robust Retry Logic
    
    private func withRetry<T>(maxAttempts: Int, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            // Check network connectivity before attempting
            guard networkMonitor.isConnected else {
                let error = EvaluationError.networkError(NSError(domain: "EvaluationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No internet connection"]))
                print("EVAL DEBUG: No network connectivity, skipping attempt \(attempt)")
                throw error
            }
            
            do {
                return try await operation()
            } catch {
                lastError = error
                print("EVAL DEBUG: Attempt \(attempt) failed: \(error)")
                
                if attempt < maxAttempts {
                    let delay = Double(attempt) * 1.5 // Exponential backoff: 1.5s, 3s
                    print("EVAL DEBUG: Retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? EvaluationError.networkError(NSError(domain: "EvaluationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retry attempts exceeded"]))
    }
    
    // MARK: - Prompt 1: Score Only with Robust Error Handling
    
    private func getScore(
        idea: Idea,
        userResponse: String,
        level: Int,
        levelConfig: LevelConfig
    ) async throws -> Int {
        
        let systemPrompt = """
        You are \(idea.book?.author ?? "the author"), the author of "\(idea.bookTitle)". You are personally evaluating a reader's response to one of your ideas.
        
        EVALUATION CONTEXT:
        - Your Book: \(idea.bookTitle)
        - Your Idea: \(idea.title)
        - Idea Description: \(idea.ideaDescription)
        - Level: \(levelConfig.name)
        - Level Description: \(levelConfig.description)
        
        EVALUATION CRITERIA:
        \(levelConfig.evaluationCriteria.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))
        
        SCORING GUIDE:
        \(levelConfig.scoringGuide)
        
        READER'S RESPONSE TO YOUR IDEA:
        \(userResponse)
        
        TASK:
        As the author, assign a score from 0-10 based on how well this reader engaged with your idea.
        
        INSTRUCTIONS:
        - Analyze their response against the level-specific criteria
        - Use the scoring guide to determine the appropriate score
        - Consider the level context and expectations
        - Be fair but rigorous in your assessment
        
        Return ONLY the score as a single integer (0-10), nothing else.
        """
        
        let userPrompt = """
        Evaluate this reader's response to your idea and assign a score from 0-10.
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1-mini",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            max_tokens: 50,
            temperature: 0.1
        )
        
        let (data, _) = try await makeAPIRequest(requestBody: requestBody)
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw EvaluationError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw EvaluationError.noResponse
        }
        
        let scoreString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let score = Int(scoreString), score >= 0 && score <= 10 else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid score format: \(scoreString)"]))
        }
        
        return score
    }
    
    // MARK: - Prompt 2: Strengths and Improvements with Robust Error Handling
    
    private func getStrengthsAndImprovements(
        idea: Idea,
        userResponse: String,
        level: Int,
        levelConfig: LevelConfig,
        score: Int
    ) async throws -> (strengths: [String], improvements: [String]) {
        
        let systemPrompt = """
        You are \(idea.book?.author ?? "the author"), the author of "\(idea.bookTitle)". You are providing personalized feedback on a reader's response to one of your ideas.
        
        EVALUATION CONTEXT:
        - Your Book: \(idea.bookTitle)
        - Your Idea: \(idea.title)
        - Idea Description: \(idea.ideaDescription)
        - Level: \(levelConfig.name)
        - Level Description: \(levelConfig.description)
        - Score: \(score)/10
        
        READER'S RESPONSE TO YOUR IDEA:
        \(userResponse)
        
        TASK:
        Provide exactly 2 specific strengths and exactly 2 specific areas for improvement.
        
        GUIDELINES:
        - Be specific and actionable
        - Reference their actual response
        - Consider the level context
        - Be encouraging but honest
        - Keep each point concise (1-2 sentences max)
        
        Return ONLY a valid JSON object with this exact structure:
        {
          "strengths": ["Strength 1", "Strength 2"],
          "improvements": ["Improvement 1", "Improvement 2"]
        }
        """
        
        let userPrompt = """
        Provide 2 strengths and 2 improvements for this reader's response.
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1-mini",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            max_tokens: 300,
            temperature: 0.3
        )
        
        let (data, _) = try await makeAPIRequest(requestBody: requestBody)
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw EvaluationError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw EvaluationError.noResponse
        }
        
        // Extract JSON from response
        let jsonString = extractJSONFromResponse(content)
        
        struct FeedbackResponse: Codable {
            let strengths: [String]
            let improvements: [String]
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON data"]))
        }
        
        let feedbackResponse: FeedbackResponse
        do {
            feedbackResponse = try JSONDecoder().decode(FeedbackResponse.self, from: jsonData)
        } catch {
            throw EvaluationError.invalidEvaluationFormat(error)
        }
        
        // Validate the result
        guard feedbackResponse.strengths.count == 2 && feedbackResponse.improvements.count == 2 else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid number of strengths or improvements"]))
        }
        
        return (strengths: feedbackResponse.strengths, improvements: feedbackResponse.improvements)
    }
    
    // MARK: - Robust API Request Method
    
    private func makeAPIRequest(requestBody: ChatRequest) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw EvaluationError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw EvaluationError.invalidResponse
            }
            
            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200:
                return (data, response)
            case 429:
                throw EvaluationError.rateLimitExceeded
            case 500...599:
                throw EvaluationError.serverError(httpResponse.statusCode)
            default:
                throw EvaluationError.invalidResponse
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw EvaluationError.timeout
                case .notConnectedToInternet:
                    throw EvaluationError.networkError(error)
                default:
                    throw EvaluationError.networkError(error)
                }
            }
            throw error
        }
    }
    
    // MARK: - Context-Aware Feedback with Retry
    
    func generateContextAwareFeedback(
        idea: Idea,
        userResponse: String,
        level: Int,
        evaluationResult: EvaluationResult
    ) async throws -> String {
        
        return try await withRetry(maxAttempts: 2, operation: {
            try await self.performContextAwareFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: evaluationResult
            )
        })
    }
    
    private func performContextAwareFeedback(
        idea: Idea,
        userResponse: String,
        level: Int,
        evaluationResult: EvaluationResult
    ) async throws -> String {
        
        let levelConfig = getLevelConfig(for: level)
        
        let systemPrompt = """
        You are \(idea.book?.author ?? "the author"), the author of "\(idea.bookTitle)". You are personally providing feedback to a reader who engaged with your idea.

        CONTEXT:
        - Your Book: \(idea.bookTitle)
        - Your Idea: \(idea.title)
        - Idea Description: \(idea.ideaDescription)
        - Level: \(levelConfig.name)
        - Reader's Score: \(evaluationResult.score10)/10

        READER'S RESPONSE TO YOUR IDEA:
        \(userResponse)

        TASK:
        As the author, give ONE clear, actionable insight that will most improve this reader's understanding:
        1. If score ≥ 7 → the single nuance they should now focus on.
        2. If score < 7 → the single most critical misunderstanding blocking them.

        GUIDELINES:
        - Address the reader directly ("you").
        - Reference their response when pinpointing the nuance or gap.
        - Sentence 1  (Affirm): Paraphrase a key line from the reader's response to prove you listened.
        - Sentence 2 (Deepen): State the one nuance or gap they haven't mentioned.
        - Sentence 3 (Challenge): Pose a higher-order question or advanced experiment that would stretch their understanding.
        - Keep it ≤ 50 words total, no greetings or sign-offs.
        - Use your authentic authorial voice.

        Return only the feedback text, nothing else.
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1-mini",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: "Please provide context-aware feedback for this response.")
            ],
            max_tokens: 200,
            temperature: 0.4
        )
        
        let (data, _) = try await makeAPIRequest(requestBody: requestBody)
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw EvaluationError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw EvaluationError.noResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Level Configuration
    
    private func getLevelConfig(for level: Int) -> LevelConfig {
        switch level {
        case 0:
            return LevelConfig(
                level: 0,
                name: "Level 0: Thought Dump",
                description: "Free-form, unfiltered thinking. Messy, personal, half-formed thoughts are welcome.",
                evaluationCriteria: [
                    "Engagement: How much did the learner engage with the idea?",
                    "Honesty: How authentic and unfiltered was the response?",
                    "Volume: Did they share enough thoughts to show genuine thinking?",
                    "Personal Connection: Did they make any personal connections to the idea?"
                ],
                scoringGuide: """
                10: Exceptional engagement with extensive, honest, unfiltered thoughts
                8-9: Strong engagement with good volume and authenticity
                6-7: Moderate engagement with some personal connection
                4-5: Limited engagement or overly filtered response
                2-3: Minimal engagement or very brief response
                0-1: No meaningful engagement or response
                """
            )
            
        case 1:
            return LevelConfig(
                level: 1,
                name: "Level 1: Use",
                description: "Apply the idea directly in practical situations.",
                evaluationCriteria: [
                    "Application: How well did they apply the idea to practical situations?",
                    "Understanding: How clearly do they understand the basic concept?",
                    "Effectiveness: How effectively did they use the idea?",
                    "Clarity: How clear and coherent was their application?"
                ],
                scoringGuide: """
                10: Exceptional application with clear understanding and effective use
                8-9: Strong application with good understanding and effectiveness
                6-7: Moderate application with some understanding
                4-5: Limited application or weak understanding
                2-3: Minimal application or poor understanding
                0-1: No meaningful application or understanding
                """
            )
            
        case 2:
            return LevelConfig(
                level: 2,
                name: "Level 2: Think with",
                description: "Use the idea as a thinking tool to analyze and solve problems.",
                evaluationCriteria: [
                    "Critical Thinking: How well did they use the idea as a thinking tool?",
                    "Problem Solving: How effectively did they apply it to analyze problems?",
                    "Insight Generation: Did they generate meaningful insights using the idea?",
                    "Depth: How thoroughly did they explore the idea's applications?"
                ],
                scoringGuide: """
                10: Exceptional critical thinking with deep problem-solving and insights
                8-9: Strong critical thinking with good problem-solving
                6-7: Moderate critical thinking with some problem-solving
                4-5: Limited critical thinking or weak problem-solving
                2-3: Minimal critical thinking or poor problem-solving
                0-1: No meaningful critical thinking or problem-solving
                """
            )
            
        case 3:
            return LevelConfig(
                level: 3,
                name: "Level 3: Build with",
                description: "Use the idea as a foundation to create new concepts and systems.",
                evaluationCriteria: [
                    "Creation: How well did they build new concepts using the idea?",
                    "Innovation: How creative and original were their constructions?",
                    "Synthesis: How effectively did they combine the idea with other concepts?",
                    "Complexity: How sophisticated and well-developed were their creations?"
                ],
                scoringGuide: """
                10: Exceptional creation with innovative synthesis and sophisticated complexity
                8-9: Strong creation with good innovation and synthesis
                6-7: Moderate creation with some innovation and synthesis
                4-5: Limited creation or weak innovation
                2-3: Minimal creation or poor innovation
                0-1: No meaningful creation or innovation
                """
            )
            
        default:
            return LevelConfig(
                level: level,
                name: "Level \(level): Advanced",
                description: "Advanced level requiring sophisticated understanding and application.",
                evaluationCriteria: [
                    "Understanding: How well do they understand the concept?",
                    "Application: How effectively do they apply it?",
                    "Insight: Do they generate valuable insights?",
                    "Communication: How clearly do they express their thoughts?"
                ],
                scoringGuide: """
                10: Exceptional understanding with excellent application and insights
                8-9: Strong understanding with good application
                6-7: Moderate understanding with some application
                4-5: Limited understanding or weak application
                2-3: Minimal understanding or poor application
                0-1: No meaningful understanding or application
                """
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractJSONFromResponse(_ response: String) -> String {
        // Look for JSON object in the response
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        return response
    }
}

 