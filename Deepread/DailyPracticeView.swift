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
    // Map cloned review question IDs -> source queue items
    @State private var reviewQuestionToQueueItem: [UUID: ReviewQueueItem] = [:]
    
    enum PracticeFlowState {
        case none
        case streak
    }
    
    private var testGenerationService: TestGenerationService {
        TestGenerationService(
            openAI: openAIService,
            modelContext: modelContext
        )
    }
    
    private var coverageService: CoverageService {
        CoverageService(modelContext: modelContext)
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
                        onCompletion: handleTestCompletion,
                        onExit: { showingTest = false }
                    )
                }
            }
            .sheet(isPresented: $showingPrimer) {
                PrimerView(idea: ideaForTest, openAIService: openAIService)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: .constant(currentView != .none)) {
                if currentView == .streak {
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

                // 1) Try to reuse an existing practice session (persisted mixed test)
                if let existingSession = try await fetchExistingSession(for: primaryIdea.id, type: "lesson_practice"),
                   let existingTest = existingSession.test,
                   existingTest.questions.count >= 8 {
                    print("DEBUG: Reusing existing practice session with \(existingTest.questions.count) questions")
                    await MainActor.run {
                        self.generatedTest = existingTest
                        self.isGenerating = false
                    }
                    return
                }
                
                print("DEBUG: Generating test for idea: \(primaryIdea.title)")
                
                // Generate fresh questions for the primary idea
                let freshTest = try await testGenerationService.generateTest(
                    for: primaryIdea,
                    testType: "initial"
                )
                
                // Ensure any due curveballs are queued for this book
                let curveballService = CurveballService(modelContext: modelContext)
                curveballService.ensureCurveballsQueuedIfDue(bookId: book.id.uuidString, bookTitle: book.title)

                // Get review questions from the queue (max 3 MCQ + 1 OEQ = 4 total) for this book only
                let reviewManager = ReviewQueueManager(modelContext: modelContext)
                let (mcqItems, openEndedItems) = reviewManager.getDailyReviewItems(bookId: book.id.uuidString)
                let allReviewItems = mcqItems + openEndedItems // Already limited to 3 MCQ + 1 OEQ
                
                // Use orderedQuestions to preserve the fixed internal sequence (Q6/Q8 invariants)
                let freshQuestions = freshTest.orderedQuestions

                // Partition by difficulty while preserving relative order within each group
                let easyFresh = freshQuestions.filter { $0.difficulty == .easy }
                var mediumFresh = freshQuestions.filter { $0.difficulty == .medium }
                var hardFresh = freshQuestions.filter { $0.difficulty == .hard }

                // Enforce fixed placement within groups:
                // - Reframe (OpenEnded) should be last within Medium (overall Q6)
                if let idx = mediumFresh.firstIndex(where: { $0.bloomCategory == .reframe && $0.type == .openEnded }) {
                    let reframe = mediumFresh.remove(at: idx)
                    mediumFresh.append(reframe)
                }

                // - HowWield (OpenEnded) should be last within Hard (overall Q8)
                if let idx = hardFresh.firstIndex(where: { $0.bloomCategory == .howWield && $0.type == .openEnded }) {
                    let howWield = hardFresh.remove(at: idx)
                    hardFresh.append(howWield)
                }
                
                // Generate review questions and keep mapping to their queue items
                var reviewPairs: [(ReviewQueueItem, Question)] = []
                if !allReviewItems.isEmpty {
                    let generated = try await testGenerationService.generateReviewQuestionsFromQueue(allReviewItems)
                    reviewPairs = Array(zip(allReviewItems, generated))
                    // Sort by difficulty ascending for nicer flow
                    reviewPairs.sort { lhs, rhs in
                        lhs.1.difficulty.pointValue < rhs.1.difficulty.pointValue
                    }
                    print("DEBUG: Added \(generated.count) review questions")
                }
                
                // Combine in proper order: Easy → Medium → Hard for both fresh and review
                var allQuestions: [Question] = []
                let freshOrdered = easyFresh + mediumFresh + hardFresh
                allQuestions.append(contentsOf: freshOrdered)
                let orderedReviewQuestions = reviewPairs.map { $0.1 }
                allQuestions.append(contentsOf: orderedReviewQuestions)
                
                // Create combined test (persisted as the session's test)
                test = Test(
                    ideaId: primaryIdea.id,
                    ideaTitle: primaryIdea.title,
                    bookTitle: book.title,
                    testType: "mixed"
                )
                
                // Clone questions to attach to the mixed test cleanly
                var combined: [Question] = []
                // Map from generated review question id -> queue item
                let sourceMap: [UUID: ReviewQueueItem] = Dictionary(uniqueKeysWithValues: reviewPairs.map { ($0.1.id, $0.0) })
                var newMap: [UUID: ReviewQueueItem] = [:]
                for (index, q) in allQuestions.enumerated() {
                    let cloned = Question(
                        ideaId: q.ideaId,
                        type: q.type,
                        difficulty: q.difficulty,
                        bloomCategory: q.bloomCategory,
                        questionText: q.questionText,
                        options: q.options,
                        correctAnswers: q.correctAnswers,
                        orderIndex: index,
                        isCurveball: q.isCurveball
                    )
                    combined.append(cloned)
                    if let src = sourceMap[q.id] {
                        newMap[cloned.id] = src
                    }
                }
                reviewQuestionToQueueItem = newMap
                
                // Persist mixed test, questions and session on MainActor
                try await MainActor.run {
                    self.modelContext.insert(test)
                    for q in combined {
                        q.test = test
                        test.questions.append(q)
                        self.modelContext.insert(q)
                    }
                    try self.modelContext.save()

                    let session = PracticeSession(
                        ideaId: primaryIdea.id,
                        bookId: book.id.uuidString,
                        type: "lesson_practice",
                        status: "ready",
                        configVersion: 1
                    )
                    session.test = test
                    self.modelContext.insert(session)
                    try self.modelContext.save()
                }

                print("DEBUG: Generated and saved mixed test with \(test.questions.count) questions (\(freshTest.questions.count) fresh + \(combined.count - freshTest.questions.count) review)")
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
    
    private func handleTestCompletion(_ attempt: TestAttempt, _ didIncrementStreak: Bool) {
        completedAttempt = attempt
        showingTest = false
        
        // Fetch responses explicitly using the attemptId
        let attemptId = attempt.id
        let descriptor = FetchDescriptor<QuestionResponse>(
            predicate: #Predicate<QuestionResponse> { response in
                response.attemptId == attemptId
            }
        )
        
        var fetchedResponses: [QuestionResponse] = []
        if let responses = try? modelContext.fetch(descriptor) {
            print("DEBUG: Fetched \(responses.count) responses for attempt \(attempt.id)")
            fetchedResponses = responses
            attempt.responses = responses
            // Debug: Print the fetched responses
            for (index, response) in responses.enumerated() {
                print("DEBUG: Fetched response \(index): questionId=\(response.questionId), isCorrect=\(response.isCorrect)")
            }
            
            // Force save to ensure the relationship is persisted
            try? modelContext.save()
            print("DEBUG: Saved attempt with \(attempt.responses.count) responses")
        } else {
            print("DEBUG: Failed to fetch responses for attempt \(attempt.id)")
        }
        
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
            
            var completedItems: [ReviewQueueItem] = []
            for response in reviewResponses where response.isCorrect {
                if let item = reviewQuestionToQueueItem[response.questionId] {
                    completedItems.append(item)
                } else if let q = test.questions.first(where: { $0.id == response.questionId }), let srcId = q.sourceQueueItemId {
                    let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == srcId })
                    if let item = try? modelContext.fetch(fetch).first { completedItems.append(item) }
                }
            }
            reviewManager.markItemsAsCompleted(completedItems)

            // Handle curveball pass/fail and mastery
            let curveService = CurveballService(modelContext: modelContext)
            for response in reviewResponses {
                var mapped: ReviewQueueItem?
                if let m = reviewQuestionToQueueItem[response.questionId] { mapped = m }
                else if let q = test.questions.first(where: { $0.id == response.questionId }), let srcId = q.sourceQueueItemId {
                    let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == srcId })
                    mapped = try? modelContext.fetch(fetch).first
                }
                guard let item = mapped, item.isCurveball else { continue }
                if response.isCorrect {
                    curveService.markCurveballResult(ideaId: item.ideaId, bookId: book.id.uuidString, passed: true)
                    let targetId = item.ideaId
                    let ideaDescriptor = FetchDescriptor<Idea>(
                        predicate: #Predicate<Idea> { idea in idea.id == targetId }
                    )
                    if let masteredIdea = try? modelContext.fetch(ideaDescriptor).first {
                        masteredIdea.masteryLevel = 3
                    }
                } else {
                    item.isCompleted = true
                    curveService.markCurveballResult(ideaId: item.ideaId, bookId: book.id.uuidString, passed: false)
                }
            }
        }
        
        // Update mastery for the lesson
        print("DEBUG: generatedTest is \(generatedTest != nil ? "not nil" : "nil")")
        print("DEBUG: selectedLesson is \(selectedLesson != nil ? "not nil" : "nil")")
        
        if let test = generatedTest, let lesson = selectedLesson {
            // Pass the fetched responses directly since attempt.responses might not be working
            updateCoverageFromAttempt(attempt: attempt, test: test, lesson: lesson, fetchedResponses: fetchedResponses)
        } else {
            print("DEBUG: WARNING - Cannot update coverage: test or lesson is nil")
        }
        
        // Decide whether to show streak view based on today's first completion
        print("DEBUG: Test completed - didIncrementStreak=\(didIncrementStreak)")
        print("DEBUG: Attempt score: \(attempt.score), responses: \(attempt.responses.count)")

        if didIncrementStreak {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { currentView = .streak }
            }
        } else {
            // No streak celebration today; finish flow immediately
            if let onComplete = onPracticeComplete {
                print("DEBUG: ✅ Completing practice without streak overlay")
                onComplete()
            } else {
                print("DEBUG: ❌ onPracticeComplete callback is nil!")
            }
        }
    }
    
    private func updateCoverageFromAttempt(attempt: TestAttempt, test: Test, lesson: GeneratedLesson, fetchedResponses: [QuestionResponse] = []) {
        let bookId = book.id.uuidString
        print("DEBUG: updateCoverageFromAttempt called")
        print("DEBUG: Updating coverage for lesson \(lesson.lessonNumber), book \(bookId)")
        print("DEBUG: Attempt ID: \(attempt.id)")
        print("DEBUG: Attempt has \(attempt.responses.count) responses")
        print("DEBUG: fetchedResponses has \(fetchedResponses.count) responses")
        print("DEBUG: Test has \(test.questions.count) questions")
        
        // Use fetched responses if available, otherwise fall back to attempt.responses
        let responsesToUse = fetchedResponses.isEmpty ? attempt.responses : fetchedResponses
        print("DEBUG: Using \(responsesToUse.count) responses for coverage calculation")
        
        // Debug: Print all responses
        for (index, response) in responsesToUse.enumerated() {
            print("DEBUG: Response \(index): questionId=\(response.questionId), isCorrect=\(response.isCorrect), userAnswer=\(response.userAnswer)")
        }
        
        // Debug: Print all question IDs in the test
        for question in test.questions {
            print("DEBUG: Test question - id: \(question.id), ideaId: '\(question.ideaId)', bloom: \(question.bloomCategory.rawValue)")
        }
        
        // Group responses by idea
        var responsesByIdea: [String: [(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String, bloomCategory: String)]] = [:]
        
        for response in responsesToUse {
            print("DEBUG: Processing response with questionId: \(response.questionId), isCorrect: \(response.isCorrect)")
            if let question = test.questions.first(where: { $0.id == response.questionId }) {
                let ideaId = question.ideaId
                print("DEBUG: Found matching question - ideaId: '\(ideaId)', bloom: \(question.bloomCategory.rawValue)")
                if responsesByIdea[ideaId] == nil {
                    responsesByIdea[ideaId] = []
                }
                
                let conceptTested = question.bloomCategory.rawValue
                responsesByIdea[ideaId]?.append((
                    questionId: question.id.uuidString,
                    isCorrect: response.isCorrect,
                    questionText: question.questionText,
                    conceptTested: conceptTested,
                    bloomCategory: question.bloomCategory.rawValue
                ))
                
                print("DEBUG: Response for idea \(ideaId): \(response.isCorrect ? "CORRECT" : "WRONG")")
            } else {
                print("DEBUG: WARNING - No question found for response with questionId: \(response.questionId)")
            }
        }
        
        print("DEBUG: Found responses for \(responsesByIdea.count) ideas")
        
        // Update coverage for each idea
        for (ideaId, responses) in responsesByIdea {
            print("DEBUG: Updating coverage for idea \(ideaId) with \(responses.count) responses")
            coverageService.updateCoverageFromLesson(
                ideaId: ideaId,
                bookId: bookId,
                responses: responses
            )
        }
        
        // Check if lesson is completed (80% or higher accuracy)
        let totalQuestions = responsesToUse.count
        let correctAnswers = responsesToUse.filter { $0.isCorrect }.count
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
                    let coverage = coverageService.getCoverage(for: reviewId, bookId: bookId)
                    if let reviewData = coverage.reviewStateData,
                       var reviewState = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewData) {
                        reviewState = FSRSScheduler.calculateNextReview(
                            currentState: reviewState,
                            performance: performance
                        )
                        coverage.reviewStateData = try? JSONEncoder().encode(reviewState)
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
                // Invalidate existing session if present
                if let existingSession = try await fetchExistingSession(for: primaryIdea.id, type: "lesson_practice") {
                    await MainActor.run {
                        self.modelContext.delete(existingSession)
                        try? self.modelContext.save()
                    }
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
            
            // Re-run generatePractice() to assemble and persist a new mixed test
            await generatePractice()
        } catch {
            print("ERROR: Failed to refresh practice: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }

    // MARK: - Session Helpers
    private func fetchExistingSession(for ideaId: String, type: String) async throws -> PracticeSession? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PracticeSession>(
                predicate: #Predicate { s in
                    s.ideaId == ideaId && s.type == type && s.status == "ready"
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try self.modelContext.fetch(descriptor).first
        }
    }
}

// MARK: - Results View
// REMOVED: ResultsView struct - We're using TestResultsView only now
// The second results screen was redundant and causing confusion with different accuracy calculations
