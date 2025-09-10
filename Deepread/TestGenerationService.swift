import Foundation
import SwiftData
import OSLog

// MARK: - Test Generation Service

class TestGenerationService {
    private let logger = Logger(subsystem: "com.deepread.app", category: "TestGeneration")
    // Helper function to randomize options and update correct answer index
    private func randomizeOptions(_ options: [String], correctIndices: [Int]) -> (options: [String], correctIndices: [Int]) {
        // Create array of indices paired with options
        let indexedOptions = Array(options.enumerated())
        
        // Shuffle the indexed options
        let shuffled = indexedOptions.shuffled()
        
        // Extract the new options order
        let newOptions = shuffled.map { $0.element }
        
        // Map old correct indices to new positions
        let newCorrectIndices = correctIndices.map { oldIndex in
            shuffled.firstIndex(where: { $0.offset == oldIndex }) ?? 0
        }
        
        return (newOptions, newCorrectIndices)
    }
    
    private let openAI: OpenAIService
    private let modelContext: ModelContext
    
    init(openAI: OpenAIService, modelContext: ModelContext) {
        self.openAI = openAI
        self.modelContext = modelContext
    }
    
    // MARK: - Test Retrieval
    
    func getTest(for idea: Idea, testType: String = "initial") -> Test? {
        let ideaId = idea.id
        let descriptor = FetchDescriptor<Test>(
            predicate: #Predicate<Test> { test in
                test.ideaId == ideaId && test.testType == testType
            }
        )
        
        do {
            let tests = try modelContext.fetch(descriptor)
            // Return the most recent test for this idea and type
            let sorted = tests.sorted { $0.createdAt > $1.createdAt }
            if let candidate = sorted.first {
                let minCount = (testType == "review") ? 1 : 8
                if candidate.questions.count >= minCount {
                    return candidate
                } else {
                    // Delete incomplete/invalid test to avoid getting stuck with partial data
                    logger.debug("Discarding invalid existing test (\(candidate.questions.count) questions); regenerating…")
                    modelContext.delete(candidate)
                    try? modelContext.save()
                }
            }
            return nil
        } catch {
            logger.error("Error fetching test: \(String(describing: error))")
            return nil
        }
    }
    
    // MARK: - Main Test Generation
    
    func generateTest(for idea: Idea, testType: String = "initial", previousMistakes: [QuestionResponse]? = nil) async throws -> Test {
        logger.debug("Checking for existing \(testType, privacy: .public) test for idea: \(idea.title, privacy: .public)")
        
        // Check if test already exists
        if let existingTest = getTest(for: idea, testType: testType) {
            logger.debug("Found existing test with \(existingTest.questions.count) questions, created at \(existingTest.createdAt, privacy: .public)")
            
            // Log the order of questions in the existing test
            logger.debug("Existing test question order:")
            for (index, q) in existingTest.orderedQuestions.enumerated() {
                logger.debug("  Q\(index + 1): \(q.bloomCategory.rawValue) - \(q.type.rawValue) - orderIndex: \(q.orderIndex)")
            }
            
            return existingTest
        }
        
        logger.debug("No existing test found, generating new \(testType, privacy: .public) test for idea: \(idea.title, privacy: .public)")
        
        // Create test container
        let test = Test(
            ideaId: idea.id,
            ideaTitle: idea.title,
            bookTitle: idea.bookTitle,
            testType: testType
        )
        
        // Generate questions based on test type
        let questions: [Question]
        if testType == "review" && previousMistakes != nil {
            questions = try await generateReviewQuestions(for: idea, mistakes: previousMistakes!)
        } else {
            questions = try await generateInitialQuestions(for: idea)
        }
        
        // Add questions to test (ensure they're sorted by orderIndex)
        test.questions = questions.sorted { $0.orderIndex < $1.orderIndex }
        questions.forEach { $0.test = test }
        
        // Save to database
        modelContext.insert(test)
        try modelContext.save()
        
        return test
    }
    
    // MARK: - Refresh Test (Force Regeneration)
    
    func refreshTest(for idea: Idea, testType: String = "initial") async throws -> Test {
        logger.debug("Refreshing \(testType, privacy: .public) test for idea: \(idea.title, privacy: .public)")
        
        // Delete existing test if it exists
        if let existingTest = getTest(for: idea, testType: testType) {
            logger.debug("Deleting existing test created at \(existingTest.createdAt, privacy: .public)")
            modelContext.delete(existingTest)
            try modelContext.save()
        }
        
        // Generate new test (will not find existing one since we just deleted it)
        return try await generateTest(for: idea, testType: testType)
    }
    
    // MARK: - Retry Test Generation (focused on incorrect answers)
    
    func generateRetryTest(for idea: Idea, incorrectResponses: [QuestionResponse]) async throws -> Test {
        logger.debug("Generating retry test for idea: \(idea.title, privacy: .public) with \(incorrectResponses.count) incorrect responses")
        
        // Create retry test container
        let test = Test(
            ideaId: idea.id,
            ideaTitle: idea.title,
            bookTitle: idea.bookTitle,
            testType: "retry"
        )
        
        var questions: [Question] = []
        var orderIndex = 0
        
        // Generate new questions targeting the same concepts that were missed
        for incorrectResponse in incorrectResponses {
            guard let originalQuestion = incorrectResponse.question else { continue }
            
            // Generate a new question of the same type/difficulty/bloom category but different content
            let newQuestion = try await generateQuestion(
                for: idea,
                type: originalQuestion.type,
                difficulty: originalQuestion.difficulty,
                bloomCategory: originalQuestion.bloomCategory,
                orderIndex: orderIndex,
                isReview: true
            )
            
            questions.append(newQuestion)
            orderIndex += 1
        }
        
        // Add questions to test (ensure they're sorted by orderIndex)
        test.questions = questions.sorted { $0.orderIndex < $1.orderIndex }
        questions.forEach { $0.test = test }
        
        // Save to database
        modelContext.insert(test)
        try modelContext.save()
        
        return test
    }
    
    // MARK: - Initial Test Generation (8 questions)
    
    private func generateInitialQuestions(for idea: Idea) async throws -> [Question] {
        var questions: [Question] = []
        
        // Fixed order with specific question types and difficulties:
        // Q1: Recall (Easy, MCQ)
        // Q2: Apply (Easy, MCQ)  
        // Q3: WhyImportant (Medium, MCQ)
        // Q4: WhenUse (Medium, MCQ)
        // Q5: Contrast (Medium, MCQ)
        // Q6: Reframe (Medium, Open-ended)
        // Q7: Critique (Hard, MCQ)
        // Q8: HowWield (Hard, Open-ended)
        
        let categoryDistribution: [(BloomCategory, QuestionDifficulty, QuestionType)] = [
            (.recall, .easy, .mcq),           // Q1
            (.apply, .easy, .mcq),            // Q2
            (.whyImportant, .medium, .mcq),   // Q3
            (.whenUse, .medium, .mcq),        // Q4
            (.contrast, .medium, .mcq),       // Q5
            (.reframe, .medium, .openEnded),  // Q6 - Open-ended for reframing
            (.critique, .hard, .mcq),         // Q7
            (.howWield, .hard, .openEnded)    // Q8 - Open-ended for how to wield
        ]
        
        // Generate questions in the fixed order
        for (index, (category, difficulty, type)) in categoryDistribution.enumerated() {
            let question = try await generateQuestion(
                for: idea,
                type: type,
                difficulty: difficulty,
                bloomCategory: category,
                orderIndex: index
            )
            questions.append(question)
            logger.debug("Generated Q\(index + 1): \(category.rawValue) - \(type.rawValue) - orderIndex: \(index)")
        }
        
        // Verify order before returning
        logger.debug("Final question order:")
        for (index, q) in questions.enumerated() {
            logger.debug("  Q\(index + 1): \(q.bloomCategory.rawValue) - \(q.type.rawValue) - orderIndex: \(q.orderIndex)")
        }
        
        return questions
    }
    
    // MARK: - Review Question Generation from Queue
    
    func generateReviewQuestionsFromQueue(_ queueItems: [ReviewQueueItem]) async throws -> [Question] {
        var questions: [Question] = []
        var orderIndex = 0
        
        for item in queueItems {
            // Generate a similar question testing the same concept
            let question = try await generateSimilarQuestion(
                from: item,
                orderIndex: orderIndex
            )
            questions.append(question)
            orderIndex += 1
        }
        
        return questions
    }
    
    private func generateSimilarQuestion(from queueItem: ReviewQueueItem, orderIndex: Int) async throws -> Question {
        // Fetch the idea for context
        let targetIdeaId = queueItem.ideaId
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.id == targetIdeaId
            }
        )
        
        guard let idea = try modelContext.fetch(descriptor).first else {
            throw TestGenerationError.generationFailed("Idea not found")
        }
        
        // Generate a similar question with the same parameters but different content
        let systemPrompt = """
        You are an expert educational content creator. Generate a NEW question that tests the SAME concept as the original question below, but with DIFFERENT content/examples.
        
        Original Question: \(queueItem.originalQuestionText)
        Question Type: \(queueItem.questionType.rawValue)
        Difficulty: \(queueItem.difficulty.rawValue)
        Bloom's Level: \(queueItem.bloomCategory.rawValue)
        
        Requirements:
        - Test the SAME underlying concept
        - Use DIFFERENT examples or scenarios
        - Keep the same difficulty level
        - Keep the same question type (\(queueItem.questionType.rawValue))
        
        \(formatRequirements(for: queueItem.questionType, difficulty: queueItem.difficulty))
        
        Output Format:
        Return ONLY a JSON object with this structure:
        {
            "question": "The new question text",
            "options": ["Option 1", "Option 2", "Option 3", "Option 4"],  // Only for MCQ
            "correct": [0]  // Index of correct answer (0-based)
        }
        
        For open-ended questions, omit options and correct fields.
        """
        
        let userPrompt = """
        Generate a similar but different question for:
        
        Idea: \(idea.title)
        Description: \(idea.ideaDescription)
        
        The question should test the same concept as the original but with fresh content.
        """
        
        let response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.8,  // Slightly higher for variety
            maxTokens: 500
        )
        
        let (questionText, options, correctAnswers) = try parseQuestionResponse(response, type: queueItem.questionType)
        
        // Randomize options if they exist
        let finalOptions: [String]?
        let finalCorrectAnswers: [Int]?
        if let opts = options, let correct = correctAnswers {
            let (shuffled, newCorrect) = randomizeOptions(opts, correctIndices: correct)
            finalOptions = shuffled
            finalCorrectAnswers = newCorrect
        } else {
            finalOptions = options
            finalCorrectAnswers = correctAnswers
        }
        
        return Question(
            ideaId: queueItem.ideaId,
            type: queueItem.questionType,
            difficulty: queueItem.difficulty,
            bloomCategory: queueItem.bloomCategory,
            questionText: questionText,
            options: finalOptions,
            correctAnswers: finalCorrectAnswers,
            orderIndex: orderIndex,
            isCurveball: queueItem.isCurveball,
            sourceQueueItemId: queueItem.id
        )
    }
    
    // MARK: - Review Test Generation (focused on mistakes)
    
    private func generateReviewQuestions(for idea: Idea, mistakes: [QuestionResponse]) async throws -> [Question] {
        var questions: [Question] = []
        var orderIndex = 0
        
        // Group mistakes by Bloom category to understand gaps
        let mistakeCategories = analyzeMistakePatterns(mistakes)
        
        // Generate targeted questions for each mistake pattern
        for (category, count) in mistakeCategories {
            // Generate 1-2 questions targeting this specific gap
            let numQuestions = min(count, 2)
            for _ in 0..<numQuestions {
                let difficulty = determineDifficultyForReview(category)
                let questionType = [QuestionType.mcq, .msq, .openEnded].randomElement()!
                
                questions.append(try await generateQuestion(
                    for: idea,
                    type: questionType,
                    difficulty: difficulty,
                    bloomCategory: category,
                    orderIndex: orderIndex,
                    isReview: true
                ))
                orderIndex += 1
            }
        }
        
        // Fill remaining slots with new questions following the same pattern
        while questions.count < 8 {
            let (category, difficulty, type) = getQuestionConfigForSlot(questions.count)
            
            questions.append(try await generateQuestion(
                for: idea,
                type: type,
                difficulty: difficulty,
                bloomCategory: category,
                orderIndex: orderIndex
            ))
            orderIndex += 1
        }
        
        return questions
    }
    
    // MARK: - Individual Question Generation
    
    private func generateQuestion(
        for idea: Idea,
        type: QuestionType,
        difficulty: QuestionDifficulty,
        bloomCategory: BloomCategory,
        orderIndex: Int,
        isReview: Bool = false
    ) async throws -> Question {
        
        let systemPrompt = createSystemPrompt(for: type, difficulty: difficulty, bloomCategory: bloomCategory)
        let userPrompt = createUserPrompt(for: idea, type: type, bloomCategory: bloomCategory, isReview: isReview)
        
        let response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.7,
            maxTokens: 500
        )
        
        // Parse the response based on question type
        let (questionText, options, correctAnswers) = try parseQuestionResponse(response, type: type)
        
        // Randomize options if they exist (MCQ and MSQ)
        let finalOptions: [String]?
        let finalCorrectAnswers: [Int]?
        if let opts = options, let correct = correctAnswers {
            let (shuffled, newCorrect) = randomizeOptions(opts, correctIndices: correct)
            finalOptions = shuffled
            finalCorrectAnswers = newCorrect
        } else {
            finalOptions = options
            finalCorrectAnswers = correctAnswers
        }
        
        return Question(
            ideaId: idea.id,
            type: type,
            difficulty: difficulty,
            bloomCategory: bloomCategory,
            questionText: questionText,
            options: finalOptions,
            correctAnswers: finalCorrectAnswers,
            orderIndex: orderIndex
        )
    }
    
    // MARK: - Prompt Creation
    
    private func createSystemPrompt(for type: QuestionType, difficulty: QuestionDifficulty, bloomCategory: BloomCategory) -> String {
        """
        You are an expert educational content creator specializing in creating questions based on Bloom's Taxonomy.
        
        Create a \(type.rawValue) question at the \(bloomCategory.rawValue) level.
        Difficulty: \(difficulty.rawValue)
        
        Question Requirements:
        - \(bloomCategory.rawValue): \(bloomDescription(for: bloomCategory))
        - Difficulty appropriate for \(difficulty.bloomLevel)
        - Clear and unambiguous wording
        - Tests deep understanding, not memorization
        
        \(formatRequirements(for: type, difficulty: difficulty))
        
        Output Format:
        Return ONLY a JSON object with this structure:
        {
            "question": "The question text",
            "options": ["Option 1", "Option 2", "Option 3", "Option 4"],  // Only for MCQ/MSQ
            "correct": [0]  // Indices of correct answers (0-based)
        }
        
        For open-ended questions, omit options and correct fields.
        """
    }
    
    private func createUserPrompt(for idea: Idea, type: QuestionType, bloomCategory: BloomCategory, isReview: Bool) -> String {
        let reviewContext = isReview ? "\nThis is a REVIEW question. Create a variation that tests the same concept from a different angle." : ""
        
        return """
        Create a \(type.rawValue) question for this idea:
        
        Title: \(idea.title)
        Description: \(idea.ideaDescription)
        Book: \(idea.bookTitle)
        
        Bloom's Level: \(bloomCategory.rawValue) - \(bloomDescription(for: bloomCategory))
        \(reviewContext)
        
        Generate a question that specifically tests the \(bloomCategory.rawValue) level of understanding.
        """
    }
    
    private func formatRequirements(for type: QuestionType, difficulty: QuestionDifficulty) -> String {
        let characterLimits = getCharacterLimits(for: difficulty)
        
        switch type {
        case .mcq:
            return """
            MCQ Requirements:
            - Exactly 4 options
            - Only 1 correct answer
            - Distractors should be plausible but clearly wrong
            - Avoid "all of the above" or "none of the above"
            - Question length: \(characterLimits.question) characters max
            - Each option: \(characterLimits.option) characters max
            """
        case .msq:
            return """
            MSQ Requirements:
            - Exactly 4 options
            - 2-3 correct answers
            - Each option should be independently evaluable
            - Clear indication that multiple answers are expected
            - Question length: \(characterLimits.question) characters max
            - Each option: \(characterLimits.option) characters max
            """
        case .openEnded:
            return """
            Open-Ended Requirements:
            - Requires 2-4 sentences to answer properly
            - Cannot be answered with yes/no
            - Has clear evaluation criteria
            - Encourages explanation and reasoning
            - Question length: \(characterLimits.question) characters max
            """
        }
    }
    
    private func getCharacterLimits(for difficulty: QuestionDifficulty) -> (question: Int, option: Int) {
        switch difficulty {
        case .easy:
            return (question: 120, option: 60)    // Short and simple
        case .medium:
            return (question: 200, option: 100)   // Moderate length
        case .hard:
            return (question: 280, option: 140)   // More complex, detailed
        }
    }
    
    // MARK: - Helper Methods
    
    private func bloomDescription(for category: BloomCategory) -> String {
        switch category {
        case .recall:
            return "Recognize or identify key aspects of the idea"
        case .reframe:
            return "Explain the idea in your own words"
        case .apply:
            return "Use the idea in a real-life context or scenario"
        case .contrast:
            return "Compare this idea with other related concepts"
        case .critique:
            return "Evaluate the flaws, limitations, or edge cases"
        case .whyImportant:
            return "Understand why this idea matters and its significance"
        case .whenUse:
            return "Identify when and where to apply this idea effectively"
        case .howWield:
            return "Master how to use this idea skillfully and effectively"
        }
    }
    
    private func parseQuestionResponse(_ response: String, type: QuestionType) throws -> (String, [String]?, [Int]?) {
        guard let data = response.data(using: .utf8) else {
            throw TestGenerationError.invalidResponse
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let question = json?["question"] as? String else {
            throw TestGenerationError.missingQuestionText
        }
        
        if type == .openEnded {
            return (question, nil, nil)
        }
        
        guard let options = json?["options"] as? [String],
              options.count == 4 else {
            throw TestGenerationError.invalidOptions
        }
        
        guard let correct = json?["correct"] as? [Int] else {
            throw TestGenerationError.missingCorrectAnswers
        }
        
        // Validate correct answers
        if type == .mcq && correct.count != 1 {
            throw TestGenerationError.invalidCorrectAnswerCount
        }
        if type == .msq && (correct.count < 2 || correct.count > 3) {
            throw TestGenerationError.invalidCorrectAnswerCount
        }
        
        return (question, options, correct)
    }
    
    private func analyzeMistakePatterns(_ mistakes: [QuestionResponse]) -> [BloomCategory: Int] {
        var patterns: [BloomCategory: Int] = [:]
        
        for mistake in mistakes {
            if let question = mistake.question {
                patterns[question.bloomCategory, default: 0] += 1
            }
        }
        
        return patterns
    }
    
    private func determineDifficultyForReview(_ category: BloomCategory) -> QuestionDifficulty {
        switch category {
        case .recall, .reframe, .whyImportant:
            return .easy
        case .apply, .whenUse:
            return .medium
        case .contrast, .critique, .howWield:
            return .hard
        }
    }
    
    private func getQuestionTypeForSlot(_ slotIndex: Int) -> QuestionType {
        // Only Q6 (index 5) and Q8 (index 7) are open-ended
        // All others are MCQ
        if slotIndex == 5 || slotIndex == 7 {
            return .openEnded
        } else {
            return .mcq
        }
    }
    
    private func getQuestionConfigForSlot(_ slotIndex: Int) -> (BloomCategory, QuestionDifficulty, QuestionType) {
        // Fixed configuration for each slot
        switch slotIndex {
        case 0: return (.recall, .easy, .mcq)           // Q1
        case 1: return (.apply, .easy, .mcq)            // Q2
        case 2: return (.whyImportant, .medium, .mcq)   // Q3
        case 3: return (.whenUse, .medium, .mcq)        // Q4
        case 4: return (.contrast, .medium, .mcq)       // Q5
        case 5: return (.reframe, .medium, .openEnded)  // Q6
        case 6: return (.critique, .hard, .mcq)         // Q7
        case 7: return (.howWield, .hard, .openEnded)   // Q8
        default: return (.recall, .easy, .mcq)          // Fallback
        }
    }
    
    private func bloomCategoryForDifficulty(_ difficulty: QuestionDifficulty) -> BloomCategory {
        switch difficulty {
        case .easy:
            return [.recall, .reframe, .whyImportant].randomElement()!
        case .medium:
            return [.apply, .whenUse].randomElement()!
        case .hard:
            return [.contrast, .critique, .howWield].randomElement()!
        }
    }
}

// MARK: - Test Generation Errors

enum TestGenerationError: Error {
    case invalidResponse
    case missingQuestionText
    case invalidOptions
    case missingCorrectAnswers
    case invalidCorrectAnswerCount
    case generationFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid response format from AI"
        case .missingQuestionText:
            return "Question text is missing"
        case .invalidOptions:
            return "Invalid or missing answer options"
        case .missingCorrectAnswers:
            return "Correct answer indices are missing"
        case .invalidCorrectAnswerCount:
            return "Invalid number of correct answers"
        case .generationFailed(let reason):
            return "Failed to generate question: \(reason)"
        }
    }
}
