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

// MARK: - HowWield (Q8) Payload

struct HowWieldSituation: Codable {
    let role: String
    let goal: String
    let constraints: [String]
    let data: [String]
}

enum HowWieldPattern: String, Codable, CaseIterable {
    case doWithWhy = "Do-With-Why"
    case repairTheMisuse = "Repair-the-Misuse"
    case tradeOffTriage = "Trade-off-Triage"
    case checklistFirstMove = "Checklist-First-Move"
    case smallNumbersApply = "Small-Numbers-Apply"
}

struct HowWieldPayload: Codable {
    let question: String
    let situation: HowWieldSituation
    let pattern: HowWieldPattern
    let keywords_used: [String]
    let rubric: [String]
    let exemplar_answer: String
    let why_this_is_howwield: String
    let relevance_score: Double
}

// MARK: - HowWield InlineCard (paragraph format)

struct HowWieldInlineCard: Codable {
    let role: String
    let goal: String
    let timebox: String
    let constraints: [String]
    let data: [String]
    let tools: [String]
    let task: String
    let rawParagraph: String
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
    var id: UUID = UUID()
    var testId: UUID?  // Reference to parent test
    var ideaId: String = ""
    var type: QuestionType = QuestionType.mcq
    var difficulty: QuestionDifficulty = QuestionDifficulty.easy
    var bloomCategory: BloomCategory = BloomCategory.recall
    var questionText: String = ""
    // Data-backed arrays for CloudKit compatibility
    var optionsData: Data?
    var correctAnswersData: Data?
    var howWieldData: Data?
    var howWieldInlineData: Data?
    var cachedWhy140: String?
    
    // Computed accessors
    var options: [String]? {
        get {
            guard let data = optionsData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            optionsData = try? JSONEncoder().encode(newValue)
        }
    }

    var howWieldPayload: HowWieldPayload? {
        get {
            guard let data = howWieldData else { return nil }
            return try? JSONDecoder().decode(HowWieldPayload.self, from: data)
        }
        set {
            howWieldData = try? JSONEncoder().encode(newValue)
        }
    }

    var howWieldInlineCard: HowWieldInlineCard? {
        get {
            guard let data = howWieldInlineData else { return nil }
            return try? JSONDecoder().decode(HowWieldInlineCard.self, from: data)
        }
        set {
            howWieldInlineData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var correctAnswers: [Int]? {
        get {
            guard let data = correctAnswersData else { return nil }
            return try? JSONDecoder().decode([Int].self, from: data)
        }
        set {
            correctAnswersData = try? JSONEncoder().encode(newValue)
        }
    }
    var orderIndex: Int = 0  // Position in test (0-8)
    var createdAt: Date = Date.now
    var isCurveball: Bool = false
    var isSpacedFollowUp: Bool = false
    // Persist mapping to source review queue item for reliable completion marking
    var sourceQueueItemId: UUID?
    
    // Relationships
    @Relationship(inverse: \Test.questions) var test: Test?
    @Relationship(deleteRule: .cascade, inverse: \QuestionResponse.question) var responses: [QuestionResponse]?
    
    init(
        ideaId: String,
        type: QuestionType,
        difficulty: QuestionDifficulty,
        bloomCategory: BloomCategory,
        questionText: String,
        options: [String]? = nil,
        correctAnswers: [Int]? = nil,
        orderIndex: Int,
        isCurveball: Bool = false,
        isSpacedFollowUp: Bool = false,
        sourceQueueItemId: UUID? = nil
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
        self.isCurveball = isCurveball
        self.isSpacedFollowUp = isSpacedFollowUp
        self.sourceQueueItemId = sourceQueueItemId
        self.cachedWhy140 = nil
    }
}

// MARK: - Test Model

@Model
final class Test {
    var id: UUID = UUID()
    var ideaId: String = ""
    var ideaTitle: String = ""
    var bookTitle: String = ""
    var testType: String = "initial"  // "initial" or "review"
    var createdAt: Date = Date.now
    var scheduledFor: Date?  // For review tests
    
    // Relationships
    @Relationship(deleteRule: .cascade) var questions: [Question]?
    @Relationship(deleteRule: .cascade) var attempts: [TestAttempt]?
    @Relationship(inverse: \Idea.tests) var idea: Idea?
    // Backlink to PracticeSession (for CloudKit inverse)
    @Relationship var practiceSession: PracticeSession?
    // Backlink to StoredLesson is removed to avoid macro circular resolution.
    
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
        self.questions = nil
        self.attempts = nil
    }
    
    // Helper to get questions by difficulty
    func questions(for difficulty: QuestionDifficulty) -> [Question] {
        (questions ?? []).filter { $0.difficulty == difficulty }.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    // Helper to get questions in order
    var orderedQuestions: [Question] {
        (questions ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }
}

// MARK: - Test Attempt Model

@Model
final class TestAttempt {
    var id: UUID = UUID()
    var testId: UUID = UUID()
    var startedAt: Date = Date.now
    var completedAt: Date?
    var score: Int = 0  // Out of 150
    // Brain Calories burned in this attempt (session)
    var brainCalories: Int = 0
    // Accuracy snapshot for this attempt
    var accuracyCorrect: Int = 0
    var accuracyTotal: Int = 0
    // Attention pauses counted in this attempt
    var attentionPauses: Int = 0
    var isComplete: Bool = false
    var masteryAchieved: MasteryType = MasteryType.none
    var retryCount: Int = 0  // Number of retry loops completed
    var currentQuestionIndex: Int = 0  // Track where user left off
    
    // Relationships
    @Relationship var responses: [QuestionResponse]?
    @Relationship var test: Test?
    
    init(testId: UUID) {
        self.id = UUID()
        self.testId = testId
        self.startedAt = Date()
        self.score = 0
        self.brainCalories = 0
        self.accuracyCorrect = 0
        self.accuracyTotal = 0
        self.attentionPauses = 0
        self.isComplete = false
        self.masteryAchieved = .none
        self.retryCount = 0
        self.currentQuestionIndex = 0
        self.responses = nil
    }
    
    // Calculate score from responses
    func calculateScore() -> Int {
        (responses ?? []).compactMap { $0.pointsEarned }.reduce(0, +)
    }
    
    // Get incorrect responses
    var incorrectResponses: [QuestionResponse] {
        (responses ?? []).filter { !$0.isCorrect }
    }
    
    // Get response for a specific question
    func response(for questionId: UUID) -> QuestionResponse? {
        (responses ?? []).first { $0.questionId == questionId }
    }
}

// MARK: - Question Response Model

@Model
final class QuestionResponse {
    var id: UUID = UUID()
    var attemptId: UUID = UUID()
    var questionId: UUID = UUID()
    var questionType: QuestionType = QuestionType.mcq
    var userAnswer: String = ""  // JSON encoded based on type
    var isCorrect: Bool = false
    var pointsEarned: Int = 0
    var answeredAt: Date = Date.now
    var retryNumber: Int = 0  // Which retry attempt (0 = initial)
    
    // For evaluation feedback
    var evaluationData: Data?  // JSON encoded evaluation result
    
    // Relationships
    @Relationship var attempt: TestAttempt?
    @Relationship var question: Question?
    
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
    var id: UUID = UUID()
    var ideaId: String = ""
    var currentTestId: UUID?
    var lastTestDate: Date?
    var nextReviewDate: Date?
    var masteryType: MasteryType = MasteryType.none
    var totalTestsTaken: Int = 0
    var averageScore: Double = 0
    
    // Track mistakes for focused review
    var mistakePatterns: Data?  // JSON encoded mistake analysis
    
    // Relationships
    @Relationship(inverse: \Idea.testProgresses) var idea: Idea?
    
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
        
        // Legacy fragile scheduling removed
    }
}

// MARK: - Stored Lesson Model
@Model
final class StoredLesson {
    var bookId: String = ""
    var lessonNumber: Int = 1
    var primaryIdeaId: String = ""
    var primaryIdeaTitle: String = ""
    var createdAt: Date = Date.now
    var isCompleted: Bool = false
    var coveragePercentage: Double = 0.0
    
    // The actual test data (generated questions) reference by ID (avoid relationship to satisfy CloudKit without inverse)
    var testId: UUID?
    
    init(bookId: String, lessonNumber: Int, primaryIdeaId: String, primaryIdeaTitle: String) {
        self.bookId = bookId
        self.lessonNumber = lessonNumber
        self.primaryIdeaId = primaryIdeaId
        self.primaryIdeaTitle = primaryIdeaTitle
        self.createdAt = Date()
        self.isCompleted = false
        self.coveragePercentage = 0.0
    }
}
