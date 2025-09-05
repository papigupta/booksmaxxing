import Foundation
import SwiftData

// MARK: - Question Types and Difficulty

enum QuestionType: String, Codable, CaseIterable {
    case mcq = "MCQ"        // Multiple Choice Question (single answer)
    case msq = "MSQ"        // Multiple Select Question (multiple answers)
    case openEnded = "OpenEnded"  // Free text response
}

enum QuestionDifficulty: String, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    
    var pointValue: Int {
        switch self {
        case .easy: return 10
        case .medium: return 15
        case .hard: return 25
        }
    }
    
    var bloomLevel: String {
        switch self {
        case .easy: return "Recall/Reframe/Why Important"
        case .medium: return "Apply/When Use"
        case .hard: return "Contrast/Critique/How Wield"
        }
    }
}

enum BloomCategory: String, Codable, CaseIterable {
    // Original Bloom's levels
    case recall = "Recall"          // Recognize or identify
    case reframe = "Reframe"        // Explain in own words
    case apply = "Apply"            // Use in real-life context
    case contrast = "Contrast"      // Compare with other ideas
    case critique = "Critique"      // Evaluate flaws and limitations
    
    // New custom levels
    case whyImportant = "WhyImportant"  // Understand significance and importance
    case whenUse = "WhenUse"            // Identify when to apply this concept
    case howWield = "HowWield"          // Master how to use this effectively
}

// MARK: - Mastery Types

enum MasteryType: String, Codable {
    case none = "None"
    case fragile = "Fragile"    // Completed initial test with retries
    case solid = "Solid"        // Passed review test with 100%
}

// MARK: - Question Model

@Model
final class Question {
    var id: UUID
    var testId: UUID?  // Reference to parent test
    var ideaId: String
    var type: QuestionType
    var difficulty: QuestionDifficulty
    var bloomCategory: BloomCategory
    var questionText: String
    @Attribute(.transformable) var options: [String]?  // For MCQ/MSQ - exactly 4 options
    @Attribute(.transformable) var correctAnswers: [Int]?  // Indices of correct answers (1 for MCQ, multiple for MSQ)
    var orderIndex: Int  // Position in test (0-8)
    var createdAt: Date
    
    // Relationship to test
    var test: Test?
    
    init(
        ideaId: String,
        type: QuestionType,
        difficulty: QuestionDifficulty,
        bloomCategory: BloomCategory,
        questionText: String,
        options: [String]? = nil,
        correctAnswers: [Int]? = nil,
        orderIndex: Int
    ) {
        self.id = UUID()
        self.ideaId = ideaId
        self.type = type
        self.difficulty = difficulty
        self.bloomCategory = bloomCategory
        self.questionText = questionText
        self.options = options
        self.correctAnswers = correctAnswers
        self.orderIndex = orderIndex
        self.createdAt = Date()
    }
}

// MARK: - Test Model

@Model
final class Test {
    var id: UUID
    var ideaId: String
    var ideaTitle: String
    var bookTitle: String
    var testType: String  // "initial" or "review"
    var createdAt: Date
    var scheduledFor: Date?  // For review tests
    
    // Relationships
    @Relationship(deleteRule: .cascade) var questions: [Question]
    @Relationship(deleteRule: .cascade) var attempts: [TestAttempt]
    var idea: Idea?
    
    init(
        ideaId: String,
        ideaTitle: String,
        bookTitle: String,
        testType: String = "initial"
    ) {
        self.id = UUID()
        self.ideaId = ideaId
        self.ideaTitle = ideaTitle
        self.bookTitle = bookTitle
        self.testType = testType
        self.createdAt = Date()
        self.questions = []
        self.attempts = []
    }
    
    // Helper to get questions by difficulty
    func questions(for difficulty: QuestionDifficulty) -> [Question] {
        questions.filter { $0.difficulty == difficulty }.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    // Helper to get questions in order
    var orderedQuestions: [Question] {
        questions.sorted { $0.orderIndex < $1.orderIndex }
    }
}

// MARK: - Test Attempt Model

@Model
final class TestAttempt {
    var id: UUID
    var testId: UUID
    var startedAt: Date
    var completedAt: Date?
    var score: Int  // Out of 150
    var isComplete: Bool
    var masteryAchieved: MasteryType
    var retryCount: Int  // Number of retry loops completed
    var currentQuestionIndex: Int  // Track where user left off
    
    // Relationships
    @Relationship(deleteRule: .cascade) var responses: [QuestionResponse]
    var test: Test?
    
    init(testId: UUID) {
        self.id = UUID()
        self.testId = testId
        self.startedAt = Date()
        self.score = 0
        self.isComplete = false
        self.masteryAchieved = .none
        self.retryCount = 0
        self.currentQuestionIndex = 0
        self.responses = []
    }
    
    // Calculate score from responses
    func calculateScore() -> Int {
        responses.compactMap { $0.pointsEarned }.reduce(0, +)
    }
    
    // Get incorrect responses
    var incorrectResponses: [QuestionResponse] {
        responses.filter { !$0.isCorrect }
    }
    
    // Get response for a specific question
    func response(for questionId: UUID) -> QuestionResponse? {
        responses.first { $0.questionId == questionId }
    }
}

// MARK: - Question Response Model

@Model
final class QuestionResponse {
    var id: UUID
    var attemptId: UUID
    var questionId: UUID
    var questionType: QuestionType
    var userAnswer: String  // JSON encoded based on type
    var isCorrect: Bool
    var pointsEarned: Int
    var answeredAt: Date
    var retryNumber: Int  // Which retry attempt (0 = initial)
    
    // For evaluation feedback
    var evaluationData: Data?  // JSON encoded evaluation result
    
    // Relationships
    var attempt: TestAttempt?
    var question: Question?
    
    init(
        attemptId: UUID,
        questionId: UUID,
        questionType: QuestionType,
        userAnswer: String,
        isCorrect: Bool = false,
        pointsEarned: Int = 0,
        retryNumber: Int = 0
    ) {
        self.id = UUID()
        self.attemptId = attemptId
        self.questionId = questionId
        self.questionType = questionType
        self.userAnswer = userAnswer
        self.isCorrect = isCorrect
        self.pointsEarned = pointsEarned
        self.answeredAt = Date()
        self.retryNumber = retryNumber
    }
    
    // Helper to decode user answer based on type
    func decodedAnswer() -> Any? {
        guard let data = userAnswer.data(using: .utf8) else { return nil }
        
        switch questionType {
        case .mcq:
            // Single integer index
            return try? JSONDecoder().decode(Int.self, from: data)
        case .msq:
            // Array of integer indices
            return try? JSONDecoder().decode([Int].self, from: data)
        case .openEnded:
            // Plain string
            return userAnswer
        }
    }
}

// MARK: - Test Progress Tracking

@Model
final class TestProgress {
    var id: UUID
    var ideaId: String
    var currentTestId: UUID?
    var lastTestDate: Date?
    var nextReviewDate: Date?
    var masteryType: MasteryType
    var totalTestsTaken: Int
    var averageScore: Double
    
    // Track mistakes for focused review
    var mistakePatterns: Data?  // JSON encoded mistake analysis
    
    // Relationships
    var idea: Idea?
    
    init(ideaId: String) {
        self.id = UUID()
        self.ideaId = ideaId
        self.masteryType = .none
        self.totalTestsTaken = 0
        self.averageScore = 0
    }
    
    // Update progress after test completion
    func updateProgress(attempt: TestAttempt) {
        lastTestDate = attempt.completedAt ?? Date()
        totalTestsTaken += 1
        
        // Update average score
        let newScore = Double(attempt.score)
        guard totalTestsTaken > 0 else { 
            averageScore = newScore
            return 
        }
        averageScore = ((averageScore * Double(totalTestsTaken - 1)) + newScore) / Double(totalTestsTaken)
        
        // Update mastery
        if attempt.masteryAchieved != .none {
            masteryType = attempt.masteryAchieved
        }
        
        // Schedule next review if achieved fragile mastery
        if masteryType == .fragile {
            nextReviewDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        }
    }
}