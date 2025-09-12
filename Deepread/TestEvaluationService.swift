import Foundation
import SwiftData
import OSLog

// MARK: - Test Evaluation Service

class TestEvaluationService {
    private let openAI: OpenAIService
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.deepread.app", category: "TestEval")
    
    init(openAI: OpenAIService, modelContext: ModelContext) {
        self.openAI = openAI
        self.modelContext = modelContext
    }
    
    // MARK: - Evaluate Complete Test
    
    func evaluateTest(_ attempt: TestAttempt, test: Test, idea: Idea) async throws -> TestEvaluationResult {
        logger.debug("Evaluating test attempt for idea: \(idea.title, privacy: .public)")
        
        var totalScore = 0
        var correctCount = 0
        var evaluationDetails: [QuestionEvaluation] = []
        
        // Evaluate each response
        for response in attempt.responses {
            guard let question = test.questions.first(where: { $0.id == response.questionId }) else {
                continue
            }
            
            let evaluation = try await evaluateQuestion(response: response, question: question, idea: idea)
            evaluationDetails.append(evaluation)
            
            if evaluation.isCorrect {
                correctCount += 1
                totalScore += evaluation.pointsEarned
            }
            
            // Update response with evaluation
            response.isCorrect = evaluation.isCorrect
            response.pointsEarned = evaluation.pointsEarned
            response.evaluationData = try? JSONEncoder().encode(evaluation)
        }
        
        // Update attempt
        attempt.score = totalScore
        attempt.completedAt = Date()
        attempt.isComplete = true
        
        // Determine mastery
        let allCorrect = correctCount == test.questions.count
        if allCorrect {
            if test.testType == "review" {
                attempt.masteryAchieved = .solid
            } else {
                // No longer using 'fragile' mastery; keep as .none for initial tests
                attempt.masteryAchieved = .none
            }
        }
        
        // Save changes
        try modelContext.save()
        
        return TestEvaluationResult(
            totalScore: totalScore,
            maxScore: 150,
            correctCount: correctCount,
            totalQuestions: test.questions.count,
            masteryAchieved: attempt.masteryAchieved,
            evaluationDetails: evaluationDetails
        )
    }
    
    // MARK: - Evaluate Individual Question
    
    func evaluateQuestion(response: QuestionResponse, question: Question, idea: Idea) async throws -> QuestionEvaluation {
        switch question.type {
        case .mcq:
            return evaluateMCQ(response: response, question: question)
        case .msq:
            return evaluateMSQ(response: response, question: question)
        case .openEnded:
            return try await evaluateOpenEnded(response: response, question: question, idea: idea)
        }
    }
    
    // MARK: - MCQ Evaluation (Simple comparison)
    
    private func evaluateMCQ(response: QuestionResponse, question: Question) -> QuestionEvaluation {
        guard let correctAnswers = question.correctAnswers,
              let correctIndex = correctAnswers.first,
              let userAnswer = response.decodedAnswer() as? Int else {
            return QuestionEvaluation(
                questionId: question.id,
                isCorrect: false,
                pointsEarned: 0,
                feedback: "Invalid answer format"
            )
        }
        
        let isCorrect = userAnswer == correctIndex
        let points = isCorrect ? question.difficulty.pointValue : 0
        
        let feedback: String
        if isCorrect {
            feedback = "Correct! Well done."
        } else {
            let correctOption = question.options?[correctIndex] ?? "Unknown"
            feedback = "The correct answer was: \(correctOption)"
        }
        
        return QuestionEvaluation(
            questionId: question.id,
            isCorrect: isCorrect,
            pointsEarned: points,
            feedback: feedback,
            correctAnswer: String(correctIndex + 1)
        )
    }
    
    // MARK: - MSQ Evaluation (Set comparison)
    
    private func evaluateMSQ(response: QuestionResponse, question: Question) -> QuestionEvaluation {
        guard let correctAnswers = question.correctAnswers,
              let userAnswers = response.decodedAnswer() as? [Int] else {
            return QuestionEvaluation(
                questionId: question.id,
                isCorrect: false,
                pointsEarned: 0,
                feedback: "Invalid answer format"
            )
        }
        
        let correctSet = Set(correctAnswers)
        let userSet = Set(userAnswers)
        
        // Check if sets match exactly
        let isCorrect = correctSet == userSet
        
        // Partial credit calculation
        let correctSelections = correctSet.intersection(userSet).count
        let incorrectSelections = userSet.subtracting(correctSet).count
        let missedSelections = correctSet.subtracting(userSet).count
        
        let points: Int
        if isCorrect {
            points = question.difficulty.pointValue
        } else if correctSelections > 0 && incorrectSelections == 0 {
            // Partial credit for some correct with no wrong selections
            guard correctSet.count > 0 else { 
                points = 0
                return QuestionEvaluation(questionId: question.id, isCorrect: false, pointsEarned: 0, feedback: "Invalid question data")
            }
            points = Int(Double(question.difficulty.pointValue) * (Double(correctSelections) / Double(correctSet.count)) * 0.5)
        } else {
            points = 0
        }
        
        let feedback: String
        if isCorrect {
            feedback = "Perfect! All correct options selected."
        } else {
            var feedbackParts: [String] = []
            if correctSelections > 0 {
                feedbackParts.append("Correct selections: \(correctSelections)")
            }
            if incorrectSelections > 0 {
                feedbackParts.append("Incorrect selections: \(incorrectSelections)")
            }
            if missedSelections > 0 {
                feedbackParts.append("Missed selections: \(missedSelections)")
            }
            feedback = feedbackParts.joined(separator: ". ")
        }
        
        return QuestionEvaluation(
            questionId: question.id,
            isCorrect: isCorrect,
            pointsEarned: points,
            feedback: feedback,
            correctAnswer: correctAnswers.map { String($0 + 1) }.joined(separator: ",")
        )
    }
    
    // MARK: - Open-Ended Evaluation (AI-powered)
    
    private func evaluateOpenEnded(response: QuestionResponse, question: Question, idea: Idea) async throws -> QuestionEvaluation {
        let userAnswer = response.userAnswer
        
        let systemPrompt = """
        You are evaluating a student's open-ended response to a question about "\(idea.title)".
        
        Question: \(question.questionText)
        Bloom's Level: \(question.bloomCategory.rawValue) - \(bloomDescription(for: question.bloomCategory))
        Difficulty: \(question.difficulty.rawValue)
        
        Scoring Guidelines:
        - Full points (\(question.difficulty.pointValue)): Comprehensive, accurate answer that fully addresses the question
        - Partial points (50-75%): Good understanding with minor gaps or imprecision
        - Minimal points (25%): Basic understanding but significant gaps
        - No points (0): Incorrect, off-topic, or demonstrates misunderstanding
        
        Evaluate based on:
        1. Accuracy of understanding
        2. Completeness of response
        3. Appropriate depth for the Bloom's level
        4. Clear communication of ideas
        
        Return ONLY a JSON object:
        {
            "score_percentage": 0-100,
            "is_correct": true/false,
            "feedback": "Specific, constructive feedback",
            "key_insight": "What they should understand"
        }
        """
        
        let userPrompt = """
        Student's Response:
        \(userAnswer)
        
        Evaluate this response and provide scoring with specific feedback.
        """
        
        let aiResponse: String
        do {
            aiResponse = try await openAI.complete(
                prompt: "\(systemPrompt)\n\n\(userPrompt)",
                model: "gpt-4.1-mini",
                temperature: 0.3,
                maxTokens: 300
            )
        } catch {
            logger.error("Failed to evaluate open-ended question: \(String(describing: error))")
            throw TestEvaluationError.evaluationFailed("Network error: \(error.localizedDescription)")
        }
        
        // Parse AI response
        logger.debug("Raw AI response received")
        
        // Try to extract JSON from response (in case there's extra text)
        let jsonString = SharedUtils.extractJSONObjectString(aiResponse)
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Failed to parse JSON from response")
            throw TestEvaluationError.invalidAIResponse
        }
        
        guard let scorePercentage = json["score_percentage"] as? Int,
              let isCorrect = json["is_correct"] as? Bool,
              let feedback = json["feedback"] as? String else {
            logger.error("Missing required JSON fields in AI response")
            throw TestEvaluationError.invalidAIResponse
        }
        
        let keyInsight = json["key_insight"] as? String
        let points = Int(Double(question.difficulty.pointValue) * Double(scorePercentage) / 100.0)
        
        return QuestionEvaluation(
            questionId: question.id,
            isCorrect: isCorrect,
            pointsEarned: points,
            feedback: feedback,
            correctAnswer: keyInsight
        )
    }
    
    // MARK: - Helper Methods
    
    // Removed in favor of SharedUtils.extractJSONObjectString
    
    private func bloomDescription(for category: BloomCategory) -> String {
        switch category {
        case .recall:
            return "Recognize or identify key aspects"
        case .reframe:
            return "Explain in own words"
        case .apply:
            return "Use in real-life context"
        case .contrast:
            return "Compare with other ideas"
        case .critique:
            return "Evaluate flaws and limitations"
        case .whyImportant:
            return "Understand significance and importance"
        case .whenUse:
            return "Identify when to apply effectively"
        case .howWield:
            return "Master skillful usage and application"
        }
    }
}

// MARK: - Evaluation Result Models

struct TestEvaluationResult {
    let totalScore: Int
    let maxScore: Int
    let correctCount: Int
    let totalQuestions: Int
    let masteryAchieved: MasteryType
    let evaluationDetails: [QuestionEvaluation]
    
    var scorePercentage: Double {
        guard maxScore > 0 else { return 0.0 }
        return Double(totalScore) / Double(maxScore) * 100
    }
    
    var allCorrect: Bool {
        correctCount == totalQuestions
    }
    
    var incorrectQuestions: [QuestionEvaluation] {
        evaluationDetails.filter { !$0.isCorrect }
    }
}

struct QuestionEvaluation: Codable {
    let questionId: UUID
    let isCorrect: Bool
    let pointsEarned: Int
    let feedback: String
    let correctAnswer: String?
    
    init(questionId: UUID, isCorrect: Bool, pointsEarned: Int, feedback: String, correctAnswer: String? = nil) {
        self.questionId = questionId
        self.isCorrect = isCorrect
        self.pointsEarned = pointsEarned
        self.feedback = feedback
        self.correctAnswer = correctAnswer
    }
}

// MARK: - Test Evaluation Errors

enum TestEvaluationError: Error {
    case invalidAIResponse
    case missingQuestion
    case evaluationFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidAIResponse:
            return "Failed to parse AI evaluation response"
        case .missingQuestion:
            return "Question not found for response"
        case .evaluationFailed(let reason):
            return "Evaluation failed: \(reason)"
        }
    }
}
