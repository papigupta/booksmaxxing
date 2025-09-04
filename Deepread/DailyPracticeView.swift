import SwiftUI
import SwiftData

struct DailyPracticeView: View {
    let book: Book
    let openAIService: OpenAIService
    let practiceType: PracticeType
    let selectedLesson: GeneratedLesson?
    let onPracticeComplete: (() -> Void)?
    
    init(book: Book, openAIService: OpenAIService, practiceType: PracticeType, selectedLesson: GeneratedLesson? = nil, onPracticeComplete: (() -> Void)? = nil) {
        self.book = book
        self.openAIService = openAIService
        self.practiceType = practiceType
        self.selectedLesson = selectedLesson
        self.onPracticeComplete = onPracticeComplete
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isGenerating = true
    @State private var generatedTest: Test?
    @State private var errorMessage: String?
    @State private var showingTest = false
    @State private var showingPrimer = false
    @State private var completedAttempt: TestAttempt?
    @State private var currentView: PracticeFlowState = .none
    
    enum PracticeFlowState {
        case none
        case results
        case streak
    }
    
    private var testGenerationService: TestGenerationService {
        TestGenerationService(
            openAI: openAIService,
            modelContext: modelContext
        )
    }
    
    private var masteryService: MasteryService {
        MasteryService(modelContext: modelContext)
    }
    
    private var ideaForTest: Idea {
        if let primaryIdeaId = selectedLesson?.primaryIdeaId,
           let idea = book.ideas.first(where: { $0.id == primaryIdeaId }) {
            return idea
        }
        
        return Idea(
            id: "daily_practice",
            title: "Daily Practice",
            description: "Mixed practice from \(book.title)",
            bookTitle: book.title,
            depthTarget: 3
        )
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isGenerating {
                    generatingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let test = generatedTest {
                    practiceReadyView(test)
                }
            }
            .navigationTitle("Practice Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DS.Colors.secondaryText)
                }
            }
            .task {
                await generatePractice()
            }
            .fullScreenCover(isPresented: $showingTest) {
                if let test = generatedTest {
                    TestView(
                        idea: ideaForTest,
                        test: test,
                        openAIService: openAIService,
                        onCompletion: handleTestCompletion
                    )
                }
            }
            .sheet(isPresented: $showingPrimer) {
                PrimerView(idea: ideaForTest, openAIService: openAIService)
            }
            .fullScreenCover(isPresented: .constant(currentView != .none)) {
                if currentView == .results, let attempt = completedAttempt, let test = generatedTest {
                    ResultsView(attempt: attempt, test: test, onContinue: {
                        print("DEBUG: Results onContinue tapped, switching to streak")
                        withAnimation {
                            currentView = .streak
                        }
                    })
                } else if currentView == .streak {
                    StreakView(onContinue: {
                        print("DEBUG: ✅ Streak onContinue tapped, completing lesson")
                        currentView = .none
                        if let onComplete = onPracticeComplete {
                            print("DEBUG: ✅ Calling onPracticeComplete callback")
                            onComplete()
                        } else {
                            print("DEBUG: ❌ onPracticeComplete callback is nil!")
                        }
                    })
                } else {
                    // Fallback for unexpected states
                    Color.red
                        .overlay(
                            Text("DEBUG: Unexpected state: \(currentView)")
                                .foregroundColor(.white)
                        )
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var generatingView: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Animation
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(DS.Colors.black)
                    .symbolEffect(.pulse)
                
                Text("Loading Your Practice Session")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
                
                Text("Preparing your personalized questions...")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Unable to Generate Practice Session")
                .font(DS.Typography.headline)
                .foregroundColor(DS.Colors.black)
            
            Text(error)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            
            Button("Try Again") {
                Task {
                    await generatePractice()
                }
            }
            .dsPrimaryButton()
            .padding(.top, DS.Spacing.md)
            
            Button("Go Back") {
                dismiss()
            }
            .dsSecondaryButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xl)
    }
    
    private func practiceReadyView(_ test: Test) -> some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                    .padding(.top, DS.Spacing.xxl)
                
                Text("Practice Ready!")
                    .font(DS.Typography.largeTitle)
                    .foregroundColor(DS.Colors.black)
                
                Text("\(test.questions.count) questions selected")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.secondaryText)
            }
            
            // Practice Overview
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Today's Session")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
                
                practiceStatsView(test)
                
                // Question breakdown
                questionBreakdownView(test)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Start button
            VStack(spacing: DS.Spacing.md) {
                Button("Start Practice") {
                    showingTest = true
                }
                .dsPrimaryButton()
                
                Button("Brush Up with Primer") {
                    showingPrimer = true
                }
                .dsSecondaryButton()
                
                Button("Generate New Questions") {
                    Task {
                        await refreshPractice()
                    }
                }
                .dsSecondaryButton()
                
                Button("Cancel") {
                    dismiss()
                }
                .dsSecondaryButton()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xl)
        }
    }
    
    private func practiceStatsView(_ test: Test) -> some View {
        HStack(spacing: DS.Spacing.xl) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Questions")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                Text("\(test.questions.count)")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
            }
            
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Est. Time")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                Text("\(test.questions.count * 2) min")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
            }
            
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Max Points")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                Text("\(test.questions.reduce(0) { $0 + $1.difficulty.pointValue })")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Colors.secondaryBackground)
        .cornerRadius(8)
    }
    
    private func questionBreakdownView(_ test: Test) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Question Mix")
                .font(DS.Typography.captionBold)
                .foregroundColor(DS.Colors.secondaryText)
            
            // Group questions by idea
            let questionsByIdea = Dictionary(grouping: test.questions) { $0.ideaId }
            
            ForEach(Array(questionsByIdea.keys.sorted()), id: \.self) { ideaId in
                if let questions = questionsByIdea[ideaId] {
                    HStack {
                        // Get idea title from the first question's ideaId
                        let ideaTitle = getIdeaTitle(for: ideaId) ?? ideaId
                        
                        Text(ideaTitle)
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.black)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(questions.count) questions")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                    }
                    .padding(.vertical, DS.Spacing.xxs)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Colors.tertiaryBackground)
        .cornerRadius(4)
    }
    
    // MARK: - Actions
    
    private func generatePractice() async {
        isGenerating = true
        errorMessage = nil
        
        do {
            let test: Test
            
            if let lesson = selectedLesson {
                print("DEBUG: Generating practice test for lesson \(lesson.lessonNumber)")
                
                // Get the primary idea for this lesson
                guard let primaryIdea = book.ideas.first(where: { $0.id == lesson.primaryIdeaId }) else {
                    throw NSError(domain: "LessonGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find idea for lesson \(lesson.lessonNumber)"])
                }
                
                print("DEBUG: Generating test for idea: \(primaryIdea.title)")
                
                // Generate fresh questions for the primary idea
                let freshTest = try await testGenerationService.generateTest(
                    for: primaryIdea,
                    testType: "initial"
                )
                
                // Get review questions from the queue (max 3 MCQ + 1 OEQ = 4 total) for this book only
                let reviewManager = ReviewQueueManager(modelContext: modelContext)
                let (mcqItems, openEndedItems) = reviewManager.getDailyReviewItems(for: book.title)
                let allReviewItems = mcqItems + openEndedItems // Already limited to 3 MCQ + 1 OEQ
                
                // Sort fresh questions by difficulty
                let freshQuestions = Array(freshTest.questions)
                let easyFresh = freshQuestions.filter { $0.difficulty == .easy }
                let mediumFresh = freshQuestions.filter { $0.difficulty == .medium }
                let hardFresh = freshQuestions.filter { $0.difficulty == .hard }
                
                // Generate and sort review questions by difficulty if available
                var easyReview: [Question] = []
                var mediumReview: [Question] = []
                var hardReview: [Question] = []
                
                if !allReviewItems.isEmpty {
                    let reviewQuestions = try await testGenerationService.generateReviewQuestionsFromQueue(allReviewItems)
                    
                    // Sort review questions by difficulty
                    easyReview = reviewQuestions.filter { $0.difficulty == .easy }
                    mediumReview = reviewQuestions.filter { $0.difficulty == .medium }
                    hardReview = reviewQuestions.filter { $0.difficulty == .hard }
                    
                    print("DEBUG: Added \(reviewQuestions.count) review questions (Easy: \(easyReview.count), Medium: \(mediumReview.count), Hard: \(hardReview.count))")
                }
                
                // Combine in proper order: Easy → Medium → Hard for both fresh and review
                var allQuestions: [Question] = []
                allQuestions.append(contentsOf: easyFresh)
                allQuestions.append(contentsOf: mediumFresh)
                allQuestions.append(contentsOf: hardFresh)
                allQuestions.append(contentsOf: easyReview)
                allQuestions.append(contentsOf: mediumReview)
                allQuestions.append(contentsOf: hardReview)
                
                // Create combined test
                test = Test(
                    ideaId: primaryIdea.id,
                    ideaTitle: primaryIdea.title,
                    bookTitle: book.title,
                    testType: "mixed"
                )
                
                // Update question order indices to reflect the new order
                for (index, question) in allQuestions.enumerated() {
                    question.orderIndex = index
                }
                
                test.questions = allQuestions
                
                print("DEBUG: Generated mixed test with \(test.questions.count) questions (\(freshTest.questions.count) fresh + \(allQuestions.count - freshTest.questions.count) review)")
            } else {
                throw NSError(domain: "LessonGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "No lesson selected"])
            }
            
            await MainActor.run {
                self.generatedTest = test
                self.isGenerating = false
            }
        } catch {
            print("ERROR: Failed to generate practice: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
    
    private func handleTestCompletion(_ attempt: TestAttempt) {
        completedAttempt = attempt
        showingTest = false
        
        // Add NEW mistakes to review queue (only from fresh questions)
        if let test = generatedTest, let primaryIdea = book.ideas.first(where: { $0.id == selectedLesson?.primaryIdeaId }) {
            let reviewManager = ReviewQueueManager(modelContext: modelContext)
            
            // Determine how many fresh questions we had (they come first in the ordered list)
            // Fresh questions are from the primary idea
            let freshQuestionCount = test.questions.filter { $0.ideaId == primaryIdea.id }.count
            
            // Only add mistakes from fresh questions to the queue
            let freshResponses = attempt.responses.filter { response in
                if let question = test.questions.first(where: { $0.id == response.questionId }) {
                    // Check if this is a fresh question (from the primary idea)
                    return question.ideaId == primaryIdea.id
                }
                return false
            }
            
            // Create a temporary attempt with only fresh responses
            let freshAttempt = TestAttempt(testId: test.id)
            freshAttempt.responses = freshResponses
            
            reviewManager.addMistakesToQueue(from: freshAttempt, test: test, idea: primaryIdea)
            
            // Mark review questions as completed if answered correctly
            let reviewResponses = attempt.responses.filter { response in
                if let question = test.questions.first(where: { $0.id == response.questionId }) {
                    return question.orderIndex >= freshQuestionCount
                }
                return false
            }
            
            // TODO: Mark the specific review items as completed based on correct answers
            print("DEBUG: Handled \(reviewResponses.count) review question responses")
        }
        
        // Update mastery for the lesson
        if let test = generatedTest, let lesson = selectedLesson {
            updateMasteryFromAttempt(attempt: attempt, test: test, lesson: lesson)
        }
        
        // Show results with a small delay to ensure proper state transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("DEBUG: Setting currentView to .results")
            print("DEBUG: Attempt score: \(attempt.score) out of \(attempt.responses.count * 150)")
            currentView = .results
        }
    }
    
    private func updateMasteryFromAttempt(attempt: TestAttempt, test: Test, lesson: GeneratedLesson) {
        let bookId = book.id.uuidString
        print("DEBUG: Updating mastery for lesson \(lesson.lessonNumber), book \(bookId)")
        
        // Group responses by idea
        var responsesByIdea: [String: [(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String)]] = [:]
        
        for response in attempt.responses {
            if let question = test.questions.first(where: { $0.id == response.questionId }) {
                let ideaId = question.ideaId
                if responsesByIdea[ideaId] == nil {
                    responsesByIdea[ideaId] = []
                }
                
                let conceptTested = question.bloomCategory.rawValue
                responsesByIdea[ideaId]?.append((
                    questionId: question.id.uuidString,
                    isCorrect: response.isCorrect,
                    questionText: question.questionText,
                    conceptTested: conceptTested
                ))
                
                print("DEBUG: Response for idea \(ideaId): \(response.isCorrect ? "CORRECT" : "WRONG")")
            }
        }
        
        print("DEBUG: Found responses for \(responsesByIdea.count) ideas")
        
        // Update mastery for each idea
        for (ideaId, responses) in responsesByIdea {
            print("DEBUG: Updating mastery for idea \(ideaId) with \(responses.count) responses")
            masteryService.updateMasteryFromLesson(
                ideaId: ideaId,
                bookId: bookId,
                responses: responses
            )
        }
        
        // Check if lesson is completed (80% or higher accuracy)
        let totalQuestions = attempt.responses.count
        let correctAnswers = attempt.responses.filter { $0.isCorrect }.count
        let accuracy = totalQuestions > 0 ? Double(correctAnswers) / Double(totalQuestions) : 0.0
        
        print("DEBUG: Lesson \(lesson.lessonNumber) completed with accuracy: \(accuracy * 100)%")
        
        // If accuracy is 80% or higher, mark lesson as completed
        if accuracy >= 0.8 {
            print("DEBUG: Lesson \(lesson.lessonNumber) passed! Unlocking next lesson.")
            // This will be handled by the completion callback
        } else {
            print("DEBUG: Lesson \(lesson.lessonNumber) needs retry (accuracy < 80%)")
        }
        
        // Handle FSRS review updates if this was a review
        if !lesson.reviewIdeaIds.isEmpty {
            for reviewId in lesson.reviewIdeaIds {
                if let responses = responsesByIdea[reviewId] {
                    let correctCount = responses.filter { $0.isCorrect }.count
                    let totalCount = responses.count
                    let performance = FSRSScheduler.performanceFromScore(
                        correctAnswers: correctCount,
                        totalQuestions: totalCount
                    )
                    
                    // Update review state
                    let mastery = masteryService.getMastery(for: reviewId, bookId: bookId)
                    if let reviewData = mastery.reviewStateData,
                       var reviewState = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewData) {
                        reviewState = FSRSScheduler.calculateNextReview(
                            currentState: reviewState,
                            performance: performance
                        )
                        mastery.reviewStateData = try? JSONEncoder().encode(reviewState)
                    }
                }
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
            print("DEBUG: Mastery updated for lesson \(lesson.lessonNumber)")
        } catch {
            print("Error saving mastery: \(error)")
        }
    }
    
    private func getIdeaTitle(for ideaId: String) -> String? {
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { $0.id == ideaId }
        )
        
        do {
            return try modelContext.fetch(descriptor).first?.title
        } catch {
            return nil
        }
    }
    
    private func refreshPractice() async {
        isGenerating = true
        errorMessage = nil
        
        do {
            let test: Test
            
            if let lesson = selectedLesson {
                print("DEBUG: Refreshing practice test for lesson \(lesson.lessonNumber)")
                
                // Get the primary idea for this lesson
                guard let primaryIdea = book.ideas.first(where: { $0.id == lesson.primaryIdeaId }) else {
                    throw NSError(domain: "LessonGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find idea for lesson \(lesson.lessonNumber)"])
                }
                
                print("DEBUG: Refreshing test for idea: \(primaryIdea.title)")
                
                // Use refreshTest to force regeneration
                test = try await testGenerationService.refreshTest(
                    for: primaryIdea,
                    testType: "initial"
                )
                
                print("DEBUG: Refreshed test with \(test.questions.count) new questions")
            } else {
                throw NSError(domain: "LessonGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "No lesson selected"])
            }
            
            await MainActor.run {
                self.generatedTest = test
                self.isGenerating = false
            }
        } catch {
            print("ERROR: Failed to refresh practice: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
}

// MARK: - Results View
private struct ResultsView: View {
    let attempt: TestAttempt
    let test: Test
    let onContinue: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                // Score summary
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: scoreIcon)
                        .font(.system(size: 64))
                        .foregroundColor(scoreColor)
                    
                    Text("Practice Complete!")
                        .font(DS.Typography.largeTitle)
                        .foregroundColor(DS.Colors.black)
                    
                    Text("Score: \(attempt.score)/\(maxScore)")
                        .font(DS.Typography.headline)
                        .foregroundColor(DS.Colors.black)
                    
                    Text("\(percentage)% Correct")
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Colors.secondaryText)
                }
                .padding(.top, DS.Spacing.xl)
                
                // Performance breakdown
                performanceBreakdown
                
                Spacer()
                
                // Actions
                Button("Continue") {
                    onContinue()
                }
                .dsPrimaryButton()
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xl)
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var maxScore: Int {
        test.questions.reduce(0) { $0 + $1.difficulty.pointValue }
    }
    
    private var percentage: Int {
        guard maxScore > 0 else { return 0 }
        return Int((Double(attempt.score) / Double(maxScore)) * 100)
    }
    
    private var scoreIcon: String {
        switch percentage {
        case 90...100: return "star.fill"
        case 70..<90: return "checkmark.circle.fill"
        case 50..<70: return "hand.thumbsup.fill"
        default: return "arrow.clockwise"
        }
    }
    
    private var scoreColor: Color {
        switch percentage {
        case 90...100: return Color.yellow
        case 70..<90: return Color.green
        case 50..<70: return DS.Colors.black
        default: return Color.red
        }
    }
    
    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Performance Breakdown")
                .font(DS.Typography.headline)
                .foregroundColor(DS.Colors.black)
            
            // Group responses by idea
            let responsesByIdea = Dictionary(grouping: attempt.responses) { response in
                test.questions.first { $0.id == response.questionId }?.ideaId ?? ""
            }
            
            ForEach(Array(responsesByIdea.keys).sorted(), id: \.self) { ideaId in
                if let responses = responsesByIdea[ideaId], !ideaId.isEmpty && !ideaId.starts(with: "daily_practice") {
                    let correctCount = responses.filter { $0.isCorrect }.count
                    let totalCount = responses.count
                    
                    HStack {
                        Text(getIdeaTitle(for: ideaId) ?? ideaId)
                            .font(DS.Typography.body)
                            .foregroundColor(DS.Colors.black)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(correctCount)/\(totalCount)")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(correctCount == totalCount ? Color.green : Color.yellow)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.secondaryBackground)
        .cornerRadius(8)
        .padding(.horizontal, DS.Spacing.lg)
    }
    
    private func getIdeaTitle(for ideaId: String) -> String? {
        test.questions.first { $0.ideaId == ideaId }?.ideaId
    }
}