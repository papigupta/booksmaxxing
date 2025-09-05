import Foundation
import SwiftData

// MARK: - Lesson Models
struct GeneratedLesson: Identifiable {
    let id = UUID()
    let lessonNumber: Int
    let title: String
    let primaryIdeaId: String
    let primaryIdeaTitle: String
    let reviewIdeaIds: [String]
    let mistakeCorrections: [(ideaId: String, concepts: [String])]
    let questionDistribution: QuestionDistribution
    let estimatedMinutes: Int
    let isUnlocked: Bool
    let isCompleted: Bool
}

struct QuestionDistribution {
    let newQuestions: Int      // Questions from primary idea
    let reviewQuestions: Int   // Questions from ideas needing review
    let correctionQuestions: Int // Re-generated mistake questions
    
    var totalQuestions: Int {
        newQuestions + reviewQuestions + correctionQuestions
    }
}

// MARK: - Lesson Generation Service
final class LessonGenerationService {
    
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
    private let modelContext: ModelContext
    private let openAIService: OpenAIService
    private let testGenerationService: TestGenerationService
    
    init(modelContext: ModelContext, openAIService: OpenAIService) {
        self.modelContext = modelContext
        self.openAIService = openAIService
        self.testGenerationService = TestGenerationService(openAI: openAIService, modelContext: modelContext)
    }
    
    // MARK: - Generate Lessons for Book
    
    /// Generate lesson structure based on book's ideas
    func generateLessonsForBook(_ book: Book) -> [GeneratedLesson] {
        let ideas = book.ideas.sortedByNumericId()
        
        var lessons: [GeneratedLesson] = []
        let bookId = book.id.uuidString
        // TODO: Fix CoverageService access issue
        // let coverageService = CoverageService(modelContext: modelContext)
        
        for (index, idea) in ideas.enumerated() {
            let lessonNumber = index + 1
            // let coverage = coverageService.getCoverage(for: idea.id, bookId: bookId)
            
            // Determine if lesson is unlocked - ONLY first lesson is unlocked initially
            let isUnlocked = lessonNumber == 1
            
            // Determine if lesson is completed
            // TODO: Restore when CoverageService is accessible
            let isCompleted = false // coverage.coveragePercentage >= 100.0 // All 8 question types covered
            
            // Get review ideas and mistakes for this lesson
            let (reviewIds, corrections) = getLessonComposition(
                currentLessonNumber: lessonNumber,
                bookId: bookId,
                allIdeas: ideas
            )
            
            // Calculate question distribution
            let distribution = calculateQuestionDistribution(
                lessonNumber: lessonNumber,
                hasReviews: !reviewIds.isEmpty,
                hasMistakes: !corrections.isEmpty
            )
            
            let lesson = GeneratedLesson(
                lessonNumber: lessonNumber,
                title: "Lesson \(lessonNumber): \(idea.title)",
                primaryIdeaId: idea.id,
                primaryIdeaTitle: idea.title,
                reviewIdeaIds: reviewIds,
                mistakeCorrections: corrections,
                questionDistribution: distribution,
                estimatedMinutes: estimateTime(distribution: distribution),
                isUnlocked: isUnlocked,
                isCompleted: isCompleted
            )
            
            lessons.append(lesson)
        }
        
        return lessons
    }
    
    // MARK: - Generate Practice Test for Lesson
    
    /// Generate actual test questions for a specific lesson
    func generatePracticeTest(for lesson: GeneratedLesson, book: Book) async throws -> Test {
        print("DEBUG: Generating practice test for lesson \(lesson.lessonNumber)")
        
        // Create test container
        let test = Test(
            ideaId: "lesson_\(lesson.lessonNumber)",
            ideaTitle: lesson.title,
            bookTitle: book.title,
            testType: "lesson_practice"
        )
        
        var allQuestions: [Question] = []
        var questionIndex = 0
        
        // 1. Generate new questions from primary idea
        if lesson.questionDistribution.newQuestions > 0 {
            let primaryIdea = book.ideas.first { $0.id == lesson.primaryIdeaId }!
            let newQuestions = try await generateQuestionsForIdea(
                primaryIdea,
                count: lesson.questionDistribution.newQuestions,
                startIndex: questionIndex
            )
            allQuestions.append(contentsOf: newQuestions)
            questionIndex += newQuestions.count
            print("DEBUG: Generated \(newQuestions.count) new questions for idea \(primaryIdea.id)")
        }
        
        // 2. Generate review questions from FSRS-scheduled ideas
        if lesson.questionDistribution.reviewQuestions > 0 && !lesson.reviewIdeaIds.isEmpty {
            for reviewId in lesson.reviewIdeaIds {
                if let reviewIdea = book.ideas.first(where: { $0.id == reviewId }) {
                    let reviewCount = min(2, lesson.questionDistribution.reviewQuestions / max(1, lesson.reviewIdeaIds.count))
                    let reviewQuestions = try await generateQuestionsForIdea(
                        reviewIdea,
                        count: reviewCount,
                        startIndex: questionIndex,
                        isReview: true
                    )
                    allQuestions.append(contentsOf: reviewQuestions)
                    questionIndex += reviewQuestions.count
                    print("DEBUG: Generated \(reviewQuestions.count) review questions for idea \(reviewId)")
                }
            }
        }
        
        // 3. Generate correction questions for mistakes
        if lesson.questionDistribution.correctionQuestions > 0 && !lesson.mistakeCorrections.isEmpty {
            for (ideaId, concepts) in lesson.mistakeCorrections {
                if let idea = book.ideas.first(where: { $0.id == ideaId }) {
                    for concept in concepts.prefix(lesson.questionDistribution.correctionQuestions) {
                        let correctionQuestion = try await generateCorrectionQuestion(
                            for: idea,
                            concept: concept,
                            index: questionIndex
                        )
                        allQuestions.append(correctionQuestion)
                        questionIndex += 1
                        print("DEBUG: Generated correction question for concept: \(concept)")
                    }
                }
            }
        }
        
        // Ensure we have exactly 8 questions
        while allQuestions.count < 8 && lesson.questionDistribution.newQuestions > 0 {
            // Fill remaining with more questions from primary idea
            if let primaryIdea = book.ideas.first(where: { $0.id == lesson.primaryIdeaId }) {
                let additionalQuestion = try await generateQuestionsForIdea(
                    primaryIdea,
                    count: 1,
                    startIndex: allQuestions.count
                ).first!
                allQuestions.append(additionalQuestion)
                print("DEBUG: Added additional question to reach 8 total")
            }
        }
        
        // Add questions to test
        for question in allQuestions {
            test.questions.append(question)
            question.test = test
        }
        
        // Don't save to SwiftData to avoid schema issues
        // The test will be used in memory only
        print("DEBUG: Practice test created with \(test.questions.count) questions")
        return test
    }
    
    // MARK: - Private Helper Methods
    
    private func getLessonComposition(
        currentLessonNumber: Int,
        bookId: String,
        allIdeas: [Idea]
    ) -> (reviewIds: [String], corrections: [(ideaId: String, concepts: [String])]) {
        
        // TODO: Restore CoverageService functionality when accessible
        // let coverageService = CoverageService(modelContext: modelContext)
        
        // For first 3 lessons, focus on pure introduction (no reviews)
        if currentLessonNumber <= 3 {
            // Check for mistakes from previous lesson only
            if currentLessonNumber > 1 {
                // let corrections = coverageService.getMistakesForCorrection(bookId: bookId, limit: 2)
                // return ([], corrections.map { ($0.ideaId, $0.mistakes.map { $0.conceptTested }) })
                return ([], [])
            }
            return ([], [])
        }
        
        // After lesson 3, start mixing in reviews based on FSRS
        // let reviewIds = coverageService.getIdeasForReview(bookId: bookId, limit: 2)
        // let corrections = coverageService.getMistakesForCorrection(bookId: bookId, limit: 2)
        // return (reviewIds, corrections.map { ($0.ideaId, $0.mistakes.map { $0.conceptTested }) })
        return ([], [])
    }
    
    private func calculateQuestionDistribution(
        lessonNumber: Int,
        hasReviews: Bool,
        hasMistakes: Bool
    ) -> QuestionDistribution {
        
        // First lesson: Pure introduction (8 new questions)
        if lessonNumber == 1 {
            return QuestionDistribution(
                newQuestions: 8,
                reviewQuestions: 0,
                correctionQuestions: 0
            )
        }
        
        // Lessons 2-3: Mostly new with some corrections
        if lessonNumber <= 3 {
            if hasMistakes {
                return QuestionDistribution(
                    newQuestions: 6,
                    reviewQuestions: 0,
                    correctionQuestions: 2
                )
            } else {
                return QuestionDistribution(
                    newQuestions: 8,
                    reviewQuestions: 0,
                    correctionQuestions: 0
                )
            }
        }
        
        // Lessons 4+: Mixed based on Duolingo + FSRS approach
        if hasReviews && hasMistakes {
            return QuestionDistribution(
                newQuestions: 5,
                reviewQuestions: 2,
                correctionQuestions: 1
            )
        } else if hasReviews {
            return QuestionDistribution(
                newQuestions: 6,
                reviewQuestions: 2,
                correctionQuestions: 0
            )
        } else if hasMistakes {
            return QuestionDistribution(
                newQuestions: 6,
                reviewQuestions: 0,
                correctionQuestions: 2
            )
        } else {
            return QuestionDistribution(
                newQuestions: 8,
                reviewQuestions: 0,
                correctionQuestions: 0
            )
        }
    }
    
    private func generateQuestionsForIdea(
        _ idea: Idea,
        count: Int,
        startIndex: Int,
        isReview: Bool = false
    ) async throws -> [Question] {
        print("DEBUG: Generating \(count) questions for idea: \(idea.title)")
        
        // Generate questions using OpenAI
        let prompt = """
        You are creating a practice test for the following concept from the book "\(idea.bookTitle)":
        
        Concept: \(idea.title)
        Description: \(idea.ideaDescription)
        
        Generate exactly \(count) multiple choice questions to test understanding of this concept.
        
        Requirements:
        1. Each question should have exactly 4 options
        2. Only ONE option should be correct
        3. Mix difficulty levels: easy (recall/understand), medium (apply), hard (analyze/evaluate)
        4. Questions should test different aspects of the concept
        5. Wrong answers should be plausible but clearly incorrect
        6. Use varied Bloom categories to ensure comprehensive coverage
        \(count == 8 ? "7. IMPORTANT: Use ALL 8 different bloom categories, one for each question" : "")
        
        Format your response as a JSON array with this structure:
        [
          {
            "question": "Question text here?",
            "options": ["Option A", "Option B", "Option C", "Option D"],
            "correctIndex": 0,
            "difficulty": "easy|medium|hard",
            "bloomCategory": "recall|reframe|whyImportant|apply|whenUse|contrast|critique|howWield"
          }
        ]
        
        IMPORTANT: Choose bloomCategory from these exact values:
        - recall: Test memory and recognition
        - reframe: Explain in own words
        - whyImportant: Understand significance
        - apply: Use in real context
        - whenUse: Identify when to apply
        - contrast: Compare with other ideas  
        - critique: Evaluate limitations
        - howWield: Master effective use
        
        Make the questions engaging and thought-provoking. Test real understanding, not just memorization.
        """
        
        do {
            let response = try await openAIService.complete(
                prompt: prompt,
                model: "gpt-4.1",
                temperature: 0.1,
                maxTokens: 1500
            )
            
            // Parse the JSON response
            guard let jsonData = (response as String).data(using: .utf8),
                  let questionData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                print("ERROR: Failed to parse OpenAI response as JSON, using fallback")
                return generateFallbackQuestions(idea: idea, count: count, startIndex: startIndex)
            }
            
            var questions: [Question] = []
            
            for (index, item) in questionData.prefix(count).enumerated() {
                guard let questionText = item["question"] as? String,
                      let options = item["options"] as? [String],
                      let correctIndex = item["correctIndex"] as? Int,
                      let difficultyStr = item["difficulty"] as? String,
                      let bloomStr = item["bloomCategory"] as? String else {
                    continue
                }
                
                let difficulty: QuestionDifficulty = {
                    switch difficultyStr.lowercased() {
                    case "easy": return .easy
                    case "hard": return .hard
                    default: return .medium
                    }
                }()
                
                let bloomCategory: BloomCategory = {
                    switch bloomStr.lowercased() {
                    case "recall": return .recall
                    case "reframe": return .reframe
                    case "whyimportant": return .whyImportant
                    case "apply": return .apply
                    case "whenuse": return .whenUse
                    case "contrast": return .contrast
                    case "critique": return .critique
                    case "howwield": return .howWield
                    case "analyze": return .contrast  // backward compatibility
                    default: return .reframe
                    }
                }()
                
                // Randomize options
                let (shuffledOptions, newCorrectIndices) = randomizeOptions(options, correctIndices: [correctIndex])
                
                let question = Question(
                    ideaId: idea.id,
                    type: .mcq,
                    difficulty: difficulty,
                    bloomCategory: bloomCategory,
                    questionText: questionText,
                    options: shuffledOptions,
                    correctAnswers: newCorrectIndices,
                    orderIndex: startIndex + index
                )
                questions.append(question)
            }
            
            // If generating 8 questions, ensure all bloom categories are covered
            if count == 8 && questions.count == 8 {
                let coveredCategories = Set(questions.map { $0.bloomCategory })
                if coveredCategories.count < 8 {
                    print("WARNING: Only \(coveredCategories.count)/8 bloom categories covered. Redistributing...")
                    let allCategories: [BloomCategory] = [.recall, .reframe, .whyImportant, .apply, .whenUse, .contrast, .critique, .howWield]
                    let missingCategories = allCategories.filter { !coveredCategories.contains($0) }
                    
                    // Replace duplicate category questions with missing categories
                    var categoryCount: [BloomCategory: Int] = [:]
                    for q in questions {
                        categoryCount[q.bloomCategory, default: 0] += 1
                    }
                    
                    for missingCategory in missingCategories {
                        // Find a duplicate category question to replace
                        if let duplicateCategory = categoryCount.first(where: { $0.value > 1 })?.key,
                           let indexToReplace = questions.firstIndex(where: { $0.bloomCategory == duplicateCategory }) {
                            questions[indexToReplace].bloomCategory = missingCategory
                            categoryCount[duplicateCategory]! -= 1
                            categoryCount[missingCategory, default: 0] += 1
                            print("Replaced duplicate \(duplicateCategory) with missing \(missingCategory)")
                        }
                    }
                }
            }
            
            // If we didn't get enough questions, fill with fallback
            while questions.count < count {
                let fallback = generateFallbackQuestions(
                    idea: idea,
                    count: 1,
                    startIndex: startIndex + questions.count
                )
                questions.append(contentsOf: fallback)
            }
            
            print("DEBUG: Successfully generated \(questions.count) questions via OpenAI")
            return questions
            
        } catch {
            print("ERROR: OpenAI generation failed: \(error), using fallback")
            return generateFallbackQuestions(idea: idea, count: count, startIndex: startIndex)
        }
    }
    
    private func generateFallbackQuestions(
        idea: Idea,
        count: Int,
        startIndex: Int
    ) -> [Question] {
        var questions: [Question] = []
        let allCategories: [BloomCategory] = [.recall, .reframe, .whyImportant, .apply, .whenUse, .contrast, .critique, .howWield]
        
        for i in 0..<count {
            let baseOptions = [
                "The correct understanding of \(idea.title)",
                "A common misconception about this concept",
                "An unrelated but plausible answer",
                "Another incorrect option"
            ]
            
            // Randomize options (correct answer is initially at index 0)
            let (shuffledOptions, newCorrectIndices) = randomizeOptions(baseOptions, correctIndices: [0])
            
            // Cycle through bloom categories to ensure variety
            let bloomCategory = allCategories[i % allCategories.count]
            
            let question = Question(
                ideaId: idea.id,
                type: .mcq,
                difficulty: .medium,
                bloomCategory: bloomCategory,
                questionText: "What is the key aspect of \(idea.title)?",
                options: shuffledOptions,
                correctAnswers: newCorrectIndices,
                orderIndex: startIndex + i
            )
            questions.append(question)
        }
        
        return questions
    }
    
    private func generateCorrectionQuestion(
        for idea: Idea,
        concept: String,
        index: Int
    ) async throws -> Question {
        print("DEBUG: Generating correction question for concept: \(concept)")
        
        let prompt = """
        A student previously missed a question about this concept from "\(idea.bookTitle)":
        
        Concept: \(idea.title)
        Description: \(idea.ideaDescription)
        Previously tested aspect: \(concept)
        
        Generate ONE new multiple choice question that tests the SAME concept but with DIFFERENT wording.
        This is a correction/review question, so make it clear and focused on understanding.
        
        Format your response as JSON:
        {
          "question": "Question text here?",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correctIndex": 0,
          "explanation": "Brief explanation of why this is correct"
        }
        """
        
        do {
            let response = try await openAIService.complete(
                prompt: prompt,
                model: "gpt-4.1",
                temperature: 0.1,
                maxTokens: 1500
            )
            
            if let jsonData = (response as String).data(using: .utf8),
               let questionData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let questionText = questionData["question"] as? String,
               let options = questionData["options"] as? [String],
               let correctIndex = questionData["correctIndex"] as? Int {
                
                // Randomize options
                let (shuffledOptions, newCorrectIndices) = randomizeOptions(options, correctIndices: [correctIndex])
                
                return Question(
                    ideaId: idea.id,
                    type: .mcq,
                    difficulty: .medium,
                    bloomCategory: .apply,
                    questionText: questionText,
                    options: shuffledOptions,
                    correctAnswers: newCorrectIndices,
                    orderIndex: index
                )
            }
        } catch {
            print("ERROR: Failed to generate correction question: \(error)")
        }
        
        // Fallback
        let fallbackOptions = [
            "The correct application of \(idea.title)",
            "A partial understanding",
            "A misconception",
            "An unrelated concept"
        ]
        
        // Randomize options (correct answer is initially at index 0)
        let (shuffledOptions, newCorrectIndices) = randomizeOptions(fallbackOptions, correctIndices: [0])
        
        return Question(
            ideaId: idea.id,
            type: .mcq,
            difficulty: .medium,
            bloomCategory: .apply,
            questionText: "Let's revisit: \(concept). How does this relate to \(idea.title)?",
            options: shuffledOptions,
            correctAnswers: newCorrectIndices,
            orderIndex: index
        )
    }
    
    
    private func getBloomCategory(for difficulty: QuestionDifficulty, isReview: Bool) -> BloomCategory {
        if isReview {
            // Simpler categories for review
            return [.recall, .reframe, .apply].randomElement()!
        }
        
        switch difficulty {
        case .easy:
            return [.recall, .reframe, .whyImportant].randomElement()!
        case .medium:
            return [.apply, .whenUse].randomElement()!
        case .hard:
            return [.contrast, .critique, .howWield].randomElement()!
        }
    }
    
    private func estimateTime(distribution: QuestionDistribution) -> Int {
        // Estimate 1 minute per question + 2 minutes buffer
        return distribution.totalQuestions + 2
    }
    
    private func isLessonCompleted(_ lessonNumber: Int, bookId: String) -> Bool {
        // Check if the lesson's primary idea has sufficient mastery
        // This would check the IdeaCoverage records
        return false  // Start with all locked except first
    }
    
    private func extractIdeaNumber(from ideaId: String) -> Int {
        let components = ideaId.split(separator: "i")
        if components.count > 1, let number = Int(components[1]) {
            return number
        }
        return 0
    }
}