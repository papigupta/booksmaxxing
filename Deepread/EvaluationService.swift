import Foundation

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

// MARK: - Evaluation Service

class EvaluationService {
    private let openAIService: OpenAIService
    
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }
    
    func evaluateSubmission(
        idea: Idea,
        userResponse: String,
        level: Int
    ) async throws -> EvaluationResult {
        
        let levelConfig = getLevelConfig(for: level)
        
        // Step 1: Get score
        let score = try await getScore(
            idea: idea,
            userResponse: userResponse,
            level: level,
            levelConfig: levelConfig
        )
        
        // Step 2: Get strengths and improvements
        let feedback = try await getStrengthsAndImprovements(
            idea: idea,
            userResponse: userResponse,
            level: level,
            levelConfig: levelConfig,
            score: score
        )
        
        return EvaluationResult(
            level: "L\(level)",
            score10: score,
            strengths: feedback.strengths,
            improvements: feedback.improvements
        )
    }
    
    // MARK: - Prompt 1: Score Only
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
        
        let requestBody = ChatRequest(
            model: "gpt-4",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: "Please score this response.")
            ],
            max_tokens: 50,
            temperature: 0.2
        )
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw EvaluationError.invalidResponse
        }
        
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw EvaluationError.decodingError(error)
        }
        
        guard let content = chatResponse.choices.first?.message.content else {
            throw EvaluationError.noResponse
        }
        
        // Parse score from response
        let scoreString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let score = Int(scoreString), score >= 0 && score <= 10 else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid score format"]))
        }
        
        return score
    }
    
    // MARK: - Prompt 2: Strengths and Improvements
    private func getStrengthsAndImprovements(
        idea: Idea,
        userResponse: String,
        level: Int,
        levelConfig: LevelConfig,
        score: Int
    ) async throws -> (strengths: [String], improvements: [String]) {
        
        let systemPrompt = """
        You are \(idea.book?.author ?? "the author"), the author of "\(idea.bookTitle)". You are personally providing feedback to a reader who engaged with your idea.
        
        CONTEXT:
        - Your Book: \(idea.bookTitle)
        - Your Idea: \(idea.title)
        - Idea Description: \(idea.ideaDescription)
        - Level: \(levelConfig.name)
        - Reader's Score: \(score)/10
        
        READER'S RESPONSE TO YOUR IDEA:
        \(userResponse)
        
        TASK:
        As the author, provide exactly 2 strengths and 2 areas for improvement based on their score of \(score)/10.
        
        INSTRUCTIONS:
        - Identify exactly 2 key strengths (be specific and actionable, as if you're personally coaching them)
        - Identify exactly 2 areas for improvement (be constructive and specific, as if you're personally guiding them)
        - Make feedback specific to their response content and score
        - Keep each item concise (1-2 sentences)
        - Use your authorial voice and perspective
        - Be encouraging but honest
        
        Return ONLY a valid JSON object with this exact structure:
        
        {
          "strengths": ["<strength1>", "<strength2>"],
          "improvements": ["<improvement1>", "<improvement2>"]
        }
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: "Please provide strengths and improvements for this response.")
            ],
            max_tokens: 300,
            temperature: 0.3
        )
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw EvaluationError.invalidResponse
        }
        
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
        
        let feedbackResponse: FeedbackResponse
        do {
            feedbackResponse = try JSONDecoder().decode(FeedbackResponse.self, from: jsonString.data(using: .utf8)!)
        } catch {
            throw EvaluationError.invalidEvaluationFormat(error)
        }
        
        // Validate the result
        guard feedbackResponse.strengths.count == 2 && feedbackResponse.improvements.count == 2 else {
            throw EvaluationError.invalidEvaluationFormat(NSError(domain: "Evaluation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid number of strengths or improvements"]))
        }
        
        return (strengths: feedbackResponse.strengths, improvements: feedbackResponse.improvements)
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
    
    func generateContextAwareFeedback(
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
        As the author, give ONE clear, actionable insight that will most improve this reader’s understanding:
        1. If score ≥ 7 → the single nuance they should now focus on.
        2. If score < 7 → the single most critical misunderstanding blocking them.

        GUIDELINES:
        - Address the reader directly (“you”).
        - Reference their response when pinpointing the nuance or gap.
        - Sentence 1  (Affirm): Paraphrase a key line from the reader’s response to prove you listened.
        - Sentence 2 (Deepen): State the one nuance or gap they haven’t mentioned.
        - Sentence 3 (Challenge): Pose a higher-order question or advanced experiment that would stretch their understanding.
        - Keep it ≤ 50 words total, no greetings or sign-offs.
        - Use your authentic authorial voice.


        Return only the feedback text, nothing else.
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4",
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: "Please provide context-aware feedback for this response.")
            ],
            max_tokens: 200,
            temperature: 0.4
        )
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw EvaluationError.invalidResponse
        }
        
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
}

 