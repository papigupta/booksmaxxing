import Foundation
import SwiftData

// MARK: - Practice Configuration
struct PracticeConfiguration {
    let newIdeasCount: Int
    let reviewIdeasCount: Int
    let questionsPerIdea: Int
    let totalQuestions: Int
    
    static let defaultV0 = PracticeConfiguration(
        newIdeasCount: 1,
        reviewIdeasCount: 2,
        questionsPerIdea: 3,
        totalQuestions: 9
    )
    
    static func configuration(for type: PracticeType) -> PracticeConfiguration {
        switch type {
        case .quick:
            return PracticeConfiguration(
                newIdeasCount: 1,  // Start with just 1 new idea (i1)
                reviewIdeasCount: 0,  // No review for first practice
                questionsPerIdea: 3,  // 3 questions per idea
                totalQuestions: 3
            )
        case .focused:
            return PracticeConfiguration(
                newIdeasCount: 2,  // 2 new ideas (i1, i2)
                reviewIdeasCount: 0,  // No review for first practice
                questionsPerIdea: 4,  // More questions per idea
                totalQuestions: 8
            )
        case .review:
            return PracticeConfiguration(
                newIdeasCount: 0,
                reviewIdeasCount: 5,
                questionsPerIdea: 2,
                totalQuestions: 10
            )
        }
    }
}

// MARK: - Practice Selection Result
struct PracticeSelectionResult {
    let newIdeas: [Idea]
    let reviewIdeas: [Idea]
    let selectionReason: [String: String] // ideaId -> reason for selection
}

// MARK: - Practice Generator Service
class PracticeGenerator {
    private let modelContext: ModelContext
    private let openAIService: OpenAIService
    private let spacedRepetitionService: SpacedRepetitionService
    private var configuration: PracticeConfiguration
    
    init(
        modelContext: ModelContext,
        openAIService: OpenAIService,
        configuration: PracticeConfiguration = .defaultV0
    ) {
        self.modelContext = modelContext
        self.openAIService = openAIService
        self.spacedRepetitionService = SpacedRepetitionService(modelContext: modelContext)
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// Generate a daily practice session for a specific book
    func generateDailyPractice(for book: Book) throws -> Test {
        return try generateDailyPractice(for: book, type: nil)
    }
    
    /// Generate a daily practice session for a specific book with practice type
    func generateDailyPractice(for book: Book, type: PracticeType) throws -> Test {
        return try generateDailyPractice(for: book, type: Optional(type))
    }
    
    private func generateDailyPractice(for book: Book, type: PracticeType?) throws -> Test {
        print("DEBUG: ULTRA-SIMPLE practice generation starting...")
        
        // Create a simple test with hardcoded questions - NO COMPLEXITY
        let practiceTest = Test(
            ideaId: "daily_practice_simple",
            ideaTitle: "Daily Practice - \(book.title)",
            bookTitle: book.title,
            testType: "daily_practice"
        )
        
        print("DEBUG: Created test container")
        
        // Create exactly 3 simple questions - NO LOOPS, NO COMPLEXITY
        let question1 = Question(
            ideaId: "simple1",
            type: .mcq,
            difficulty: .easy,
            bloomCategory: .recall,
            questionText: "What is the main concept from the first idea?",
            options: ["Correct answer", "Wrong A", "Wrong B", "Wrong C"],
            correctAnswers: [0],
            orderIndex: 0
        )
        
        let question2 = Question(
            ideaId: "simple2",
            type: .mcq,
            difficulty: .easy,
            bloomCategory: .recall,
            questionText: "What is important about this topic?",
            options: ["Right answer", "Wrong A", "Wrong B", "Wrong C"],
            correctAnswers: [0],
            orderIndex: 1
        )
        
        let question3 = Question(
            ideaId: "simple3",
            type: .mcq,
            difficulty: .easy,
            bloomCategory: .recall,
            questionText: "How would you apply this concept?",
            options: ["Best answer", "Wrong A", "Wrong B", "Wrong C"],
            correctAnswers: [0],
            orderIndex: 2
        )
        
        print("DEBUG: Created 3 simple questions")
        
        // Add questions directly
        practiceTest.questions.append(question1)
        practiceTest.questions.append(question2)
        practiceTest.questions.append(question3)
        
        question1.test = practiceTest
        question2.test = practiceTest
        question3.test = practiceTest
        
        print("DEBUG: Added questions to test")
        
        // Save - this is the only place that could fail
        modelContext.insert(practiceTest)
        try modelContext.save()
        
        print("DEBUG: ULTRA-SIMPLE practice test created successfully with 3 questions")
        return practiceTest
    }
    
    // MARK: - Selection Logic
    
    private func selectIdeasForPractice(from book: Book) -> PracticeSelectionResult {
        var newIdeas: [Idea] = []
        var reviewIdeas: [Idea] = []
        var selectionReason: [String: String] = [:]
        
        // Get all ideas from the book, sorted numerically by idea number (i1, i2, i3...)
        let allIdeas = book.ideas.sorted { idea1, idea2 in
            // Extract numeric part from idea IDs like "b1i1", "b1i2", etc.
            let num1 = extractIdeaNumber(from: idea1.id)
            let num2 = extractIdeaNumber(from: idea2.id)
            return num1 < num2
        }
        
        print("DEBUG: Ideas sorted numerically: \(allIdeas.map { $0.id })")
        
        // Start simple: For now, just take NEW (unmastered) ideas in order
        let unmasteredIdeas = allIdeas.filter { $0.masteryLevel == 0 }
        print("DEBUG: Found \(unmasteredIdeas.count) new ideas: \(unmasteredIdeas.map { $0.id })")
        
        // Select new ideas starting from i1, i2, i3...
        let newIdeaCount = min(configuration.newIdeasCount, unmasteredIdeas.count)
        if newIdeaCount > 0 {
            newIdeas = Array(unmasteredIdeas.prefix(newIdeaCount))
            for idea in newIdeas {
                selectionReason[idea.id] = "New idea - starting from \(idea.ideaNumber)"
            }
            print("DEBUG: Selected \(newIdeas.count) new ideas: \(newIdeas.map { $0.id })")
        }
        
        // For now, skip review questions to focus on new learning
        // Later we can add review logic once new question flow works
        
        return PracticeSelectionResult(
            newIdeas: newIdeas,
            reviewIdeas: reviewIdeas,
            selectionReason: selectionReason
        )
    }
    
    private func extractIdeaNumber(from ideaId: String) -> Int {
        // Extract number from "b1i1" -> 1, "b1i10" -> 10, etc.
        let components = ideaId.split(separator: "i")
        if components.count > 1, let number = Int(components[1]) {
            return number
        }
        return 0
    }
    
    private func determineQuestionCount(for idea: Idea, isNew: Bool) -> Int {
        // For v0, use fixed count per idea
        // Future versions can adjust based on importance, difficulty, etc.
        return configuration.questionsPerIdea
    }
    
    
    private func shuffleQuestionsWithDifficultyBalance(_ questions: [Question]) -> [Question] {
        // Group questions by difficulty
        let easyQuestions = questions.filter { $0.difficulty == .easy }
        let mediumQuestions = questions.filter { $0.difficulty == .medium }
        let hardQuestions = questions.filter { $0.difficulty == .hard }
        
        // Shuffle each group
        let shuffledEasy = easyQuestions.shuffled()
        let shuffledMedium = mediumQuestions.shuffled()
        let shuffledHard = hardQuestions.shuffled()
        
        // Interleave questions for balanced difficulty progression
        var result: [Question] = []
        let maxCount = max(shuffledEasy.count, shuffledMedium.count, shuffledHard.count)
        
        for i in 0..<maxCount {
            if i < shuffledEasy.count { result.append(shuffledEasy[i]) }
            if i < shuffledMedium.count { result.append(shuffledMedium[i]) }
            if i < shuffledHard.count { result.append(shuffledHard[i]) }
        }
        
        return result
    }
    
    // MARK: - Logging
    
    private func logSelection(_ selection: PracticeSelectionResult) {
        print("=== Daily Practice Selection ===")
        print("Configuration: \(configuration.newIdeasCount) new, \(configuration.reviewIdeasCount) review")
        print("\nNew Ideas (\(selection.newIdeas.count)):")
        for idea in selection.newIdeas {
            let reason = selection.selectionReason[idea.id] ?? "Unknown"
            print("  - \(idea.title) [\(idea.id)]: \(reason)")
        }
        print("\nReview Ideas (\(selection.reviewIdeas.count)):")
        for idea in selection.reviewIdeas {
            let reason = selection.selectionReason[idea.id] ?? "Unknown"
            print("  - \(idea.title) [\(idea.id)]: \(reason)")
        }
        print("================================")
    }
    
    // MARK: - Progress Update
    
    func updateProgressAfterPractice(attempt: TestAttempt, practiceTest: Test) {
        // Group responses by idea
        let responsesByIdea = Dictionary(grouping: attempt.responses) { response in
            practiceTest.questions.first { $0.id == response.questionId }?.ideaId ?? ""
        }
        
        // Update progress for each idea
        for (ideaId, responses) in responsesByIdea {
            guard !ideaId.isEmpty && !ideaId.starts(with: "daily_practice") else { continue }
            
            // Fetch the idea
            guard let idea = fetchIdea(by: ideaId) else { continue }
            
            // Calculate performance for this idea
            let correctCount = responses.filter { $0.isCorrect }.count
            let totalCount = responses.count
            let score = Int((Double(correctCount) / Double(totalCount)) * 10)
            
            // Update idea mastery based on performance
            updateIdeaMastery(idea: idea, score: score)
            
            // Update TestProgress
            if let testProgress = getOrCreateTestProgress(for: idea) {
                testProgress.lastTestDate = Date()
                testProgress.totalTestsTaken += 1
                
                // Update average score
                let newScore = Double(score * 10) // Convert to percentage
                testProgress.averageScore = ((testProgress.averageScore * Double(testProgress.totalTestsTaken - 1)) + newScore) / Double(testProgress.totalTestsTaken)
                
                // Schedule review if needed
                if idea.masteryLevel == 1 || idea.masteryLevel == 2 {
                    testProgress.nextReviewDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
                    testProgress.masteryType = .fragile
                } else if idea.masteryLevel == 3 {
                    testProgress.masteryType = .solid
                    testProgress.nextReviewDate = nil
                }
            }
            
            // Update last practiced date
            idea.lastPracticed = Date()
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Error updating progress after practice: \(error)")
        }
    }
    
    private func updateIdeaMastery(idea: Idea, score: Int) {
        // Simple mastery update based on score
        if score >= 8 {
            // Excellent performance - increase mastery
            idea.masteryLevel = min(idea.masteryLevel + 1, 3)
        } else if score >= 6 {
            // Good performance - maintain or slight increase
            if idea.masteryLevel == 0 {
                idea.masteryLevel = 1
            }
        } else {
            // Poor performance - decrease mastery but not below 0
            idea.masteryLevel = max(idea.masteryLevel - 1, 0)
        }
    }
    
    private func fetchIdea(by id: String) -> Idea? {
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { $0.id == id }
        )
        
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("Error fetching idea: \(error)")
            return nil
        }
    }
    
    private func getOrCreateTestProgress(for idea: Idea) -> TestProgress? {
        let ideaId = idea.id
        let descriptor = FetchDescriptor<TestProgress>(
            predicate: #Predicate<TestProgress> { $0.ideaId == ideaId }
        )
        
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                return existing
            }
            
            let newProgress = TestProgress(ideaId: idea.id)
            newProgress.idea = idea
            modelContext.insert(newProgress)
            return newProgress
        } catch {
            print("Error getting/creating test progress: \(error)")
            return nil
        }
    }
}

// MARK: - Errors
enum PracticeGeneratorError: LocalizedError {
    case noIdeasAvailable
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noIdeasAvailable:
            return "No ideas available for practice"
        case .generationFailed(let reason):
            return "Failed to generate practice: \(reason)"
        }
    }
}

