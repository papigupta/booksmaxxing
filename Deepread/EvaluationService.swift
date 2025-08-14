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
    let level: String        // e.g. "L1", "L2", "L3"
    let starScore: Int       // 1-3 stars
    let starDescription: String // "Getting There", "Solid Grasp", "Aha! Moment"
    let pass: Bool           // starScore >= 2
    let insightCompass: WisdomFeedback // Combined wisdom feedback
    
    // Reality Check fields (only populated when starScore < 3)
    let idealAnswer: String?          // The 3-star reference answer
    let keyGap: String?              // The fatal flaw explanation
    let hasRealityCheck: Bool        // UI flag for showing section
    
    // Backward compatibility - legacy properties
    let score10: Int         // Legacy 0-10 score computed from starScore
    let strengths: [String]  // Legacy strengths (derived from insight compass)
    let improvements: [String] // Legacy improvements (derived from insight compass)
    let mastery: Bool        // Legacy mastery indicator
}

// Structured author feedback for dense non-fiction (universal)
struct AuthorFeedback: Codable {
    let rubric: [String]         // e.g., ["definition_accuracy","interplay","application_example"]
    let verdict: String
    let oneBigThing: String
    let evidence: [String]
    let upgrade: String
    let transferCue: String
    let microDrill: String
    let memoryHook: String
    let edgeOrTrap: String?
    let confidence: Double?
}

// Enhanced wisdom-centered feedback structure
struct WisdomFeedback: Codable {
    let wisdomOpening: String      // Philosophical reframing insight
    let rootCause: String          // Fundamental mental model error
    let missingFoundation: String  // Authoritative knowledge gap
    let elevatedPerspective: String // Higher-order understanding
    let nextLevelPrep: String      // Preparation for advanced mastery
    let personalizedWisdom: String // Custom wisdom based on their patterns
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
    private let openAI: OpenAIService
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.networkMonitor = EvaluationNetworkMonitor()
        self.openAI = OpenAIService(apiKey: apiKey)
        
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
        level: Int,
        prompt: String
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
            try await self.performEvaluation(idea: idea, userResponse: userResponse, level: level, prompt: prompt)
        })
    }
    
    // Fetches structured, compact, level-aware feedback without altering scoring logic
    func generateStructuredFeedback(
        idea: Idea,
        userResponse: String,
        level: Int,
        evaluationResult: EvaluationResult
    ) async throws -> AuthorFeedback {
        try await withRetry(maxAttempts: 2) {
            try await self.performStructuredFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: evaluationResult
            )
        }
    }
    
    // Enhanced wisdom-centered evaluation with Master Oogway + Author Knowledge
    func generateWisdomFeedback(
        idea: Idea,
        userResponse: String,
        level: Int,
        evaluationResult: EvaluationResult
    ) async throws -> WisdomFeedback {
        try await withRetry(maxAttempts: 2) {
            try await self.performWisdomFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: evaluationResult
            )
        }
    }
    
    private func performEvaluation(
        idea: Idea,
        userResponse: String,
        level: Int,
        prompt: String
    ) async throws -> EvaluationResult {
        
        print("EVAL DEBUG: Starting star-based evaluation for idea: \(idea.title), level: \(level)")
        
        let levelName = getLevelName(level)
        let levelCriteria = getLevelCriteria(level)
        
        let systemPrompt = """
        You are evaluating a user's response using a 3-star system focused on insight discovery, not performance assessment.
        
        CONTEXT:
        - Book: \(idea.bookTitle) 
        - Author: \(idea.book?.author ?? "the author")
        - Idea: \(idea.title)
        - Idea Description: \(idea.ideaDescription)
        - Level: \(levelName)
        - Level Focus: \(levelCriteria)
        
        THE SPECIFIC QUESTION USER WAS ASKED:
        \(prompt)
        
        USER RESPONSE:
        \(userResponse)
        
        STAR SCORING (robust criteria):
        ⭐ (1) Getting There: 
        - Basic engagement but significant gaps remain
        - Missing key connections or understanding
        - Needs substantial work before advancing
        - Examples: vague responses, off-topic, surface-level only
        
        ⭐⭐ (2) Solid Grasp: 
        - Good understanding with minor gaps
        - Makes relevant connections
        - Ready to advance to next level
        - Examples: addresses the prompt well, shows comprehension, some insights
        
        ⭐⭐⭐ (3) Aha! Moment: 
        - Deep insight achieved, breakthrough thinking
        - Goes beyond requirements with original connections
        - Demonstrates mastery-level understanding
        - Examples: profound insights, creative applications, connects to bigger picture
        
        LEVEL-SPECIFIC CRITERIA:
        Level 1 (Why Care): Must explain significance and real-world importance with concrete examples
        Level 2 (When Use): Must identify triggers and application contexts with specific scenarios  
        Level 3 (How Wield): Must demonstrate creative/critical extension with original applications
        
        REALITY CHECK GENERATION:
        - Ideal answer is standalone - no awareness of user's response
        - Focus on deep consequences and stakes, not surface-level benefits
        - Key gap should reveal what they're missing about why this truly matters
        - Show the real-world impact of ignoring vs applying this concept
        
        COMBINED EVALUATION: Return ONLY this exact JSON structure:
        {
          "starScore": 1 | 2 | 3,
          "starDescription": "Getting There" | "Solid Grasp" | "Aha! Moment",
          "pass": boolean,
          "insightCompass": {
            "wisdomOpening": "20-35 words: Big picture insight or reframe",
            "rootCause": "20-30 words: Logical gap or thinking error analysis", 
            "missingFoundation": "25-40 words: Key knowledge they need to understand",
            "elevatedPerspective": "25-40 words: Expert-level pattern or professional insight",
            "nextLevelPrep": "20-35 words: Next learning step guidance",
            "personalizedWisdom": "20-30 words: Tailored insight for their thinking style"
          },
          "idealAnswer": "IF starScore < 3: Write a standalone 3-star response to THE SPECIFIC QUESTION above. Answer exactly what was asked. No awareness of the user's answer. Focus on deep consequences, stakes, and real-world impact. Use concrete examples and human language. Sound like someone who truly understands. ELSE: null",
          "keyGap": "IF starScore < 3: The specific deeper insight they're missing. Focus on consequences, stakes, or the underlying mechanism. What would make them go 'oh shit, now I see why this actually matters.' Not process, but impact. ELSE: null"
        }
        
        IMPORTANT: 
        - Use simple, clear language (8th grade level)
        - Be specific to their actual response
        - Focus on insight and discovery, not judgment
        - Each wisdom field must stay within word limits
        - Ensure JSON is valid and parseable
        """
        
        let model = "gpt-4.1"  // Use full model for combined evaluation
        let temperature: Double = 0.7  // Higher creativity for Reality Check generation
        let maxTokens: Int = 1200  // More tokens for detailed Reality Check content
        
        let raw = try await openAI.complete(
            prompt: systemPrompt,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        print("EVAL DEBUG: Raw API response: \(raw)")
        
        // Parse the combined JSON response
        let parsed = try parseStarEvaluation(raw)
        
        // Compute legacy compatibility values
        let legacyScore = convertStarToLegacyScore(starScore: parsed.starScore)
        let legacyStrengths = extractStrengths(from: parsed.insightCompass)
        let legacyImprovements = extractImprovements(from: parsed.insightCompass)
        let legacyMastery = parsed.starScore == 3 // 3 stars = mastery
        
        let result = EvaluationResult(
            level: "L\(level)",
            starScore: parsed.starScore,
            starDescription: parsed.starDescription,
            pass: parsed.pass,
            insightCompass: parsed.insightCompass,
            idealAnswer: parsed.idealAnswer,
            keyGap: parsed.keyGap,
            hasRealityCheck: parsed.starScore < 3,
            score10: legacyScore,
            strengths: legacyStrengths,
            improvements: legacyImprovements,
            mastery: legacyMastery
        )
        
        print("EVAL DEBUG: Star evaluation completed - Score: \(parsed.starScore) stars, Pass: \(parsed.pass)")
        return result
    }
    
    // MARK: - Helper Methods for Star System
    
    private func getLevelName(_ level: Int) -> String {
        switch level {
        case 1: return "Level 1: Why Care"
        case 2: return "Level 2: When Use"  
        case 3: return "Level 3: How Wield"
        default: return "Level \(level): Advanced"
        }
    }
    
    private func getLevelCriteria(_ level: Int) -> String {
        switch level {
        case 1: return "Understand why this idea matters and its significance"
        case 2: return "Identify when to recall and apply this idea effectively"
        case 3: return "Wield this idea creatively or critically to extend thinking"
        default: return "Advanced application and mastery"
        }
    }
    
    // MARK: - JSON Parsing for Star System
    
    private struct StarEvaluationResponse: Codable {
        let starScore: Int
        let starDescription: String
        let pass: Bool
        let insightCompass: WisdomFeedback
        let idealAnswer: String?
        let keyGap: String?
    }
    
    private func parseStarEvaluation(_ rawResponse: String) throws -> StarEvaluationResponse {
        // Clean and extract JSON
        let jsonString = extractJSONFromResponse(rawResponse)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "EvaluationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"]))
        }
        
        do {
            let response = try JSONDecoder().decode(StarEvaluationResponse.self, from: jsonData)
            
            // Validate star score is within bounds
            guard response.starScore >= 1 && response.starScore <= 3 else {
                throw EvaluationError.invalidEvaluationFormat(NSError(domain: "EvaluationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid star score: \(response.starScore)"]))
            }
            
            // Validate pass logic (starScore >= 2)
            let expectedPass = response.starScore >= 2
            if response.pass != expectedPass {
                print("EVAL DEBUG: Pass logic inconsistency - correcting pass to \(expectedPass)")
                return StarEvaluationResponse(
                    starScore: response.starScore,
                    starDescription: response.starDescription,
                    pass: expectedPass,
                    insightCompass: response.insightCompass,
                    idealAnswer: response.idealAnswer,
                    keyGap: response.keyGap
                )
            }
            
            return response
        } catch {
            print("EVAL DEBUG: JSON parsing failed: \(error)")
            throw EvaluationError.decodingError(error)
        }
    }
    
    private func extractJSONFromResponse(_ response: String) -> String {
        // Look for JSON object in the response
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
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
            max_tokens: 100,
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
            max_tokens: 500,
            temperature: 0.7
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
            model: "gpt-4.1",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: "Please provide context-aware feedback for this response.")
            ],
            max_tokens: 700,
            temperature: 1
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
    
    private func performStructuredFeedback(
        idea: Idea,
        userResponse: String,
        level: Int,
        evaluationResult: EvaluationResult
    ) async throws -> AuthorFeedback {

        let levelConfig = getLevelConfig(for: level)

        // Hard constraints to avoid generic fluff
        let bannedPhrases = [
            "could improve clarity and nuance",
            "accurately defines",
            "relatable example",
            "deepen understanding",
            "this interplay",
            "recognizing this",
            "in summary",
            "overall",
            "add more detail",
            "be more specific"
        ].joined(separator: ", ")

        // STRONGER SPEC — quote-anchored, level-aware, no fluff
        func makePrompt(regenerate: Bool) -> String {
            """
            You are \(idea.book?.author ?? "the author"). Provide compact, surgical feedback that works for any dense non-fiction idea.
            Use ONLY Idea Description + Reader Response. NO external facts.

            CONTEXT
            - Book: \(idea.bookTitle)
            - Idea: \(idea.title)
            - Idea Description: \(idea.ideaDescription)
            - Level: \(levelConfig.name) — \(levelConfig.description)
            - Reader Score: \(evaluationResult.score10)/10

            READER RESPONSE
            \(userResponse)

            RULES
            - Ground every judgment in the user's own words: include 1–2 verbatim quotes (3–12 words each) from the response in `evidence`.
            - `verdict` MUST follow: "Met X/Y: <met items>; Missed: <missed items> — because <short reason tied to a quote>."
            - Pick 2–3 items for `rubric` from: definition_accuracy, interplay, application_example, limitations, transfer, reasoning_quality, clarity.
            - `oneBigThing`: exactly ONE surgical improvement (if score >= 7) OR the ONE most costly misconception (if < 7). Must reference a phrase from the response.
            - `upgrade`: rewrite ONE weak sentence from the response in the user's likely voice, ≤ 22 words, no hedging words (no "may", "might", "could").
            - `transferCue`: one If/Then rule with a concrete trigger and concrete action.
            - `microDrill`: 60–90 seconds; concrete; something the reader can do NOW; starts with an imperative verb.
            - `memoryHook`: 5–7 words, punchy, no commas or quotes.
            - `edgeOrTrap`: optional; if included, name a subtle boundary or common confusion in ≤ 18 words.
            - Avoid generic filler. Do NOT use any of these phrases: \(bannedPhrases).
            \(regenerate ? "- THIS IS A REGENERATION. Prior output was generic. Make every field specific and quote-anchored." : "")

            OUTPUT
            Return ONLY valid JSON with keys:
            {
              "rubric": ["definition_accuracy","..."],
              "verdict": "Met X/Y: ...",
              "oneBigThing": "...",
              "evidence": ["\"<quote 1>\"", "\"<quote 2>\""],
              "upgrade": "...",
              "transferCue": "If <trigger>, then <action>.",
              "microDrill": "<imperative action in 1–2 sentences>",
              "memoryHook": "<5–7 words>",
              "edgeOrTrap": "<optional>" ,
              "confidence": 0.0
            }
            """
        }

        // one-shot caller
        @discardableResult
        func callOnce(regenerate: Bool) async throws -> AuthorFeedback {
            let requestBody = ChatRequest(
                model: "gpt-4.1-mini",
                messages: [
                    Message(role: "system", content: makePrompt(regenerate: regenerate)),
                    Message(role: "user", content: "Return ONLY the JSON object now.")
                ],
                max_tokens: 520,
                temperature: 0.1   // be deterministic & sharp
            )

            let (data, _) = try await makeAPIRequest(requestBody: requestBody)
            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = chatResponse.choices.first?.message.content else {
                throw EvaluationError.noResponse
            }
            let jsonString = extractJSONFromResponse(content)
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON data"]))
            }
            let feedback = try JSONDecoder().decode(AuthorFeedback.self, from: jsonData)
            return feedback
        }

        // lightweight validator to reject bland/generic results
        func isGeneric(_ fb: AuthorFeedback) -> Bool {
            // must have quotes in evidence and not be empty
            let quotesOK = fb.evidence.contains { $0.contains("\"") || $0.contains("\"") || $0.contains("'") } && !fb.evidence.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !quotesOK { return true }

            // verdict must contain "Met " and "Missed" and "because"
            let v = fb.verdict.lowercased()
            let verdictOK = v.contains("met ") && v.contains("missed") && v.contains("because")
            if !verdictOK { return true }

            // reject banned phrases & hedging in upgrade
            let banned = ["could", "might", "may", "overall", "in summary", "deepen understanding", "clarity and nuance"]
            if banned.contains(where: { v.contains($0) }) { return true }
            let up = fb.upgrade.lowercased()
            if up.contains("could ") || up.contains("might ") || up.contains("may ") { return true }

            // memory hook length 2..8 words
            let hookWords = fb.memoryHook.split(separator: " ")
            if hookWords.count < 2 || hookWords.count > 8 { return true }

            return false
        }

        // try once; if generic, regenerate with stricter instruction
        var feedback = try await callOnce(regenerate: false)
        if isGeneric(feedback) {
            feedback = try await callOnce(regenerate: true)
        }

        // final guardrails
        guard !feedback.oneBigThing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing oneBigThing"]))
        }
        return feedback
    }
    
    // MARK: - Insight Compass Multi-Perspective Feedback Implementation
    
    private func performWisdomFeedback(
        idea: Idea,
        userResponse: String,
        level: Int,
        evaluationResult: EvaluationResult
    ) async throws -> WisdomFeedback {
        
        let levelConfig = getLevelConfig(for: level)
        let authorName = idea.book?.author ?? "the author"
        
        let systemPrompt = """
        You are \(authorName), providing transformative feedback from multiple expert perspectives. Adapt your tone to be educational yet accessible - like explaining to bright students, not academic peers.
        
        CONTEXT:
        - Your Book: \(idea.bookTitle)
        - Your Idea: \(idea.title)
        - Idea Description: \(idea.ideaDescription)
        - Level: \(levelConfig.name)
        - Reader's Score: \(evaluationResult.score10)/10
        - Pass Status: \(evaluationResult.pass ? "Passed" : "Incomplete")
        
        READER'S RESPONSE:
        \(userResponse)
        
        TASK: Create perspective-based feedback with 6 viewpoints. Adapt section tone based on score:
        
        FOR HIGH SCORES (8-10): Use encouraging, nuanced language ("refine", "enhance", "next level")
        FOR MID SCORES (5-7): Use supportive, clarifying language ("clarify", "strengthen", "build on")
        FOR LOW SCORES (0-4): Use gentle, foundational language ("start with", "key insight", "think of it as")
        
        1. WISE SAGE PERSPECTIVE - The Big Picture (20-35 words):
        Share an insightful reframe or deeper truth. Simple language, profound insight. What are they really wrestling with?
        
        2. RATIONAL ANALYST PERSPECTIVE - The Logic (20-30 words):
        Identify the logical gap or thinking error. Clear, systematic. What's the flaw in their reasoning process?
        
        3. CARING TEACHER PERSPECTIVE - The Foundation (25-40 words):
        Provide the missing knowledge they need. Patient, educational. What core concept would unlock their understanding?
        
        4. MASTER CRAFTSPERSON PERSPECTIVE - The Craft (25-40 words):
        Show the deeper pattern or professional insight. Practical wisdom. How do experts actually think about this?
        
        5. FUTURE COACH PERSPECTIVE - What's Next (20-35 words):
        Guide them toward their next learning step. Forward-looking. What should they focus on to advance?
        
        6. PERSONAL MENTOR PERSPECTIVE - Just for You (20-30 words):
        Tailored insight based on their specific approach. Individual. What would help THEIR particular thinking style?
        
        STYLE REQUIREMENTS:
        - Simple, clear language (8th grade level)
        - Use author's authentic voice but simplified
        - Address them directly ("you")
        - Be specific to their actual response
        - Encouraging and constructive
        - No jargon or complex terms
        
        OUTPUT: Return ONLY valid JSON:
        {
          "wisdomOpening": "...",
          "rootCause": "...",
          "missingFoundation": "...",
          "elevatedPerspective": "...",
          "nextLevelPrep": "...",
          "personalizedWisdom": "..."
        }
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: "Provide wisdom-centered feedback for this response.")
            ],
            max_tokens: 800,
            temperature: 0.8  // Higher creativity for wisdom insights
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
        
        let jsonString = extractJSONFromResponse(content)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON data"]))
        }
        
        let wisdomFeedback: WisdomFeedback
        do {
            wisdomFeedback = try JSONDecoder().decode(WisdomFeedback.self, from: jsonData)
        } catch {
            throw EvaluationError.invalidEvaluationFormat(error)
        }
        
        return wisdomFeedback
    }
    
    // --- helpers (add privately in the same file) ---
    private func mapLevel(_ level: Int) -> EvalLevel {
        switch level {
        case 1: return .L1
        case 2: return .L2
        case 3: return .L3
        default: return .L1  // Default to L1 instead of L0
        }
    }
    
    private struct ParsedEval: Decodable {
        let score: Int
        let silverBullet: String
        let strengths: [String]
        let gaps: [String]
        let nextAction: String
        let pass: Bool
        let mastery: Bool
        
        enum CodingKeys: String, CodingKey {
            case score
            case silverBullet = "silver_bullet"
            case strengths
            case gaps
            case nextAction = "next_action"
            case pass
            case mastery
        }
    }
    
    private static func parseEvalJSON(_ raw: String) -> ParsedEval {
        // 1) Try direct JSON
        if let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(ParsedEval.self, from: data) {
            return parsed
        }
        // 2) Try to extract a JSON object substring
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            let jsonSub = String(raw[start...end])
            if let data = jsonSub.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(ParsedEval.self, from: data) {
                return parsed
            }
        }
        // 3) Fallback safe default
        return ParsedEval(
            score: 0,
            silverBullet: "Couldn't parse feedback.",
            strengths: [],
            gaps: ["Response could not be evaluated due to formatting. Try again."],
            nextAction: "Re-submit a concise response focusing on the core idea.",
            pass: false,
            mastery: false
        )
    }
    
    // MARK: - Legacy Compatibility Helper Methods
    
    private func convertStarToLegacyScore(starScore: Int) -> Int {
        switch starScore {
        case 1: return 4 // ⭐ Getting There
        case 2: return 7 // ⭐⭐ Solid Grasp  
        case 3: return 9 // ⭐⭐⭐ Aha! Moment
        default: return 0
        }
    }
    
    private func extractStrengths(from wisdom: WisdomFeedback) -> [String] {
        // Extract positive elements from the wisdom feedback
        var strengths: [String] = []
        
        // Look for positive phrases in the wisdom opening
        let wisdomText = wisdom.wisdomOpening.lowercased()
        if wisdomText.contains("good") || wisdomText.contains("strong") || wisdomText.contains("clear") {
            strengths.append("Shows clear understanding of the core concept")
        }
        if wisdomText.contains("insight") || wisdomText.contains("grasp") {
            strengths.append("Demonstrates thoughtful engagement with the material")
        }
        
        // Default strengths if none detected
        if strengths.isEmpty {
            strengths = ["Engaged with the concept", "Provided thoughtful response"]
        }
        
        return Array(strengths.prefix(2)) // Maximum 2 strengths
    }
    
    private func extractImprovements(from wisdom: WisdomFeedback) -> [String] {
        // Extract improvement areas from the wisdom feedback
        var improvements: [String] = []
        
        // Look for improvement hints in missing foundation and next level prep
        if !wisdom.missingFoundation.isEmpty {
            improvements.append(wisdom.missingFoundation)
        }
        if !wisdom.nextLevelPrep.isEmpty && improvements.count < 2 {
            improvements.append(wisdom.nextLevelPrep)
        }
        
        // Default improvements if none detected
        if improvements.isEmpty {
            improvements = ["Consider exploring deeper applications", "Look for more specific examples"]
        }
        
        return Array(improvements.prefix(2)) // Maximum 2 improvements
    }
}

 