import SwiftUI
import SwiftData

struct DailyPracticeWithReviewView: View {
    let book: Book
    let openAIService: OpenAIService
    let onPracticeComplete: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isGenerating = true
    @State private var freshQuestions: [Question] = []
    @State private var reviewQuestions: [Question] = []
    @State private var reviewQueueItems: [ReviewQueueItem] = []
    @State private var currentIdea: Idea?
    @State private var combinedTest: Test?
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
    
    private var reviewQueueManager: ReviewQueueManager {
        ReviewQueueManager(modelContext: modelContext)
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isGenerating {
                    generatingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if freshQuestions.isEmpty && reviewQuestions.isEmpty {
                    noPracticeView
                } else {
                    practiceReadyView
                }
            }
            .navigationTitle("Daily Practice")
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
                await generateDailyPractice()
            }
            .fullScreenCover(isPresented: $showingTest) {
                if let test = combinedTest {
                    TestView(
                        idea: currentIdea ?? createDailyPracticeIdea(),
                        test: test,
                        openAIService: openAIService,
                        onCompletion: handleTestCompletion,
                        onExit: { showingTest = false }
                    )
                }
            }
            .sheet(isPresented: $showingPrimer) {
                if let idea = currentIdea {
                    PrimerView(idea: idea, openAIService: openAIService)
                        .presentationDetents([.medium, .large])
                }
            }
            .fullScreenCover(isPresented: .constant(currentView != .none)) {
                if currentView == .results, let attempt = completedAttempt, let test = combinedTest {
                    ReviewTestResultsView(
                        attempt: attempt,
                        test: test,
                        book: book,
                        onContinue: {
                            withAnimation {
                                currentView = .streak
                            }
                        }
                    )
                } else if currentView == .streak {
                    StreakView(onContinue: {
                        currentView = .none
                        onPracticeComplete?()
                    })
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var generatingView: some View {
        VStack(spacing: DS.Spacing.xl) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(DS.Colors.black)
                    .symbolEffect(.pulse)
                
                Text("Preparing Daily Practice")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
                
                Text("Loading fresh content and review questions...")
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
            
            Text("Unable to Generate Practice")
                .font(DS.Typography.headline)
                .foregroundColor(DS.Colors.black)
            
            Text(error)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            
            Button("Try Again") {
                Task {
                    await generateDailyPractice()
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
    
    private var noPracticeView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("All Caught Up!")
                .font(DS.Typography.largeTitle)
                .foregroundColor(DS.Colors.black)
            
            Text("You've completed all available lessons and have no review questions pending.")
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            
            Button("Go Back") {
                dismiss()
            }
            .dsPrimaryButton()
            .padding(.top, DS.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xl)
    }
    
    private var practiceReadyView: some View {
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
                
                Text("\(freshQuestions.count + reviewQuestions.count) questions prepared")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.secondaryText)
            }
            
            // Practice Breakdown
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text("Today's Session")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
                
                // Fresh content section
                if !freshQuestions.isEmpty, let idea = currentIdea {
                    sessionSectionView(
                        title: "📚 New Learning",
                        subtitle: idea.title,
                        questions: freshQuestions,
                        color: DS.Colors.black
                    )
                }
                
                // Review section
                if !reviewQuestions.isEmpty {
                    sessionSectionView(
                        title: "🔄 Review Queue",
                        subtitle: "Reinforcing past mistakes",
                        questions: reviewQuestions,
                        color: Color.orange
                    )
                }
                
                // Stats
                statsView
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Actions
            VStack(spacing: DS.Spacing.md) {
                Button("Start Practice") {
                    showingTest = true
                }
                .dsPrimaryButton()
                
                if currentIdea != nil {
                    Button("Review Primer First") {
                        showingPrimer = true
                    }
                    .dsSecondaryButton()
                }
                
                Button("Cancel") {
                    dismiss()
                }
                .dsSecondaryButton()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xl)
        }
    }
    
    private func sessionSectionView(title: String, subtitle: String, questions: [Question], color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Typography.bodyBold)
                .foregroundColor(color)
            
            Text(subtitle)
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)
            
            HStack(spacing: DS.Spacing.md) {
                let mcqCount = questions.filter { $0.type == .mcq }.count
                let openEndedCount = questions.filter { $0.type == .openEnded }.count
                
                if mcqCount > 0 {
                    Label("\(mcqCount) MCQ", systemImage: "list.bullet")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                }
                
                if openEndedCount > 0 {
                    Label("\(openEndedCount) Open", systemImage: "text.alignleft")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statsView: some View {
        HStack(spacing: DS.Spacing.xl) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Total Questions")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                Text("\(freshQuestions.count + reviewQuestions.count)")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
            }
            
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Est. Time")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                Text("~\((freshQuestions.count + reviewQuestions.count) * 1) min")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
            }
            
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Queue Remaining")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                let queueStats = reviewQueueManager.getQueueStatistics(for: book.title)
                Text("\(queueStats.totalMCQs + queueStats.totalOpenEnded)")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Colors.secondaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func generateDailyPractice() async {
        isGenerating = true
        errorMessage = nil
        
        do {
            // For pure review sessions, we only need review questions
            // 1. Get review items from queue for this specific book
            let (mcqItems, openEndedItems) = reviewQueueManager.getDailyReviewItems(for: book.title)
            reviewQueueItems = mcqItems + openEndedItems
            
            print("🔄 REVIEW SESSION: Found \(reviewQueueItems.count) items in queue (\(mcqItems.count) MCQ, \(openEndedItems.count) Open-ended)")
            
            // 2. Generate similar questions for review items
            if !reviewQueueItems.isEmpty {
                reviewQuestions = try await testGenerationService.generateReviewQuestionsFromQueue(reviewQueueItems)
                
                // Sort review questions by difficulty for proper progression
                let easyReview = reviewQuestions.filter { $0.difficulty == .easy }
                let mediumReview = reviewQuestions.filter { $0.difficulty == .medium }
                let hardReview = reviewQuestions.filter { $0.difficulty == .hard }
                
                // Combine in difficulty order: Easy → Medium → Hard
                var sortedReviewQuestions: [Question] = []
                sortedReviewQuestions.append(contentsOf: easyReview)
                sortedReviewQuestions.append(contentsOf: mediumReview)
                sortedReviewQuestions.append(contentsOf: hardReview)
                
                reviewQuestions = sortedReviewQuestions
                
                print("🔄 REVIEW SESSION: Generated \(reviewQuestions.count) review questions (Easy: \(easyReview.count), Medium: \(mediumReview.count), Hard: \(hardReview.count))")
            }
            
            // 3. Create test with only review questions
            if !reviewQuestions.isEmpty {
                // Create a dummy idea for the review session
                currentIdea = Idea(
                    id: "review_session",
                    title: "Review Practice",
                    description: "Mixed review from multiple ideas",
                    bookTitle: book.title,
                    depthTarget: 1
                )
                combinedTest = createCombinedTest(fresh: [], review: reviewQuestions)
                print("🔄 REVIEW SESSION: Created test with \(reviewQuestions.count) questions")
            }
            
            await MainActor.run {
                self.isGenerating = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
    
    private func getNextUnlearnedIdea() -> Idea? {
        // Find the first idea that hasn't been tested yet
        let targetBookTitle = book.title
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.bookTitle == targetBookTitle && idea.masteryLevel == 0
            },
            sortBy: [SortDescriptor(\.id)]
        )
        
        do {
            let unlearnedIdeas = try modelContext.fetch(descriptor)
            return unlearnedIdeas.first
        } catch {
            print("Error fetching unlearned ideas: \(error)")
            return nil
        }
    }
    
    private func createCombinedTest(fresh: [Question], review: [Question]) -> Test {
        let test = Test(
            ideaId: currentIdea?.id ?? "daily_practice",
            ideaTitle: currentIdea?.title ?? "Daily Practice",
            bookTitle: book.title,
            testType: "daily"
        )
        
        // Combine questions with proper ordering
        var allQuestions: [Question] = []
        var orderIndex = 0
        
        // Add fresh questions first
        for question in fresh {
            question.orderIndex = orderIndex
            allQuestions.append(question)
            orderIndex += 1
        }
        
        // Add review questions
        for question in review {
            question.orderIndex = orderIndex
            allQuestions.append(question)
            orderIndex += 1
        }
        
        test.questions = allQuestions
        return test
    }
    
    private func createDailyPracticeIdea() -> Idea {
        Idea(
            id: "daily_practice",
            title: "Daily Practice",
            description: "Mixed practice session",
            bookTitle: book.title,
            depthTarget: 3
        )
    }
    
    private func handleTestCompletion(_ attempt: TestAttempt) {
        completedAttempt = attempt
        showingTest = false
        
        // Record mistakes to review queue
        if let test = combinedTest {
            let reviewManager = ReviewQueueManager(modelContext: modelContext)
            
            // Only add mistakes from fresh questions to queue
            let freshAttemptResponses = attempt.responses.filter { response in
                test.questions.first { $0.id == response.questionId }?.orderIndex ?? 0 < freshQuestions.count
            }
            
            // Create a fresh attempt for recording purposes
            let freshAttempt = TestAttempt(testId: test.id)
            freshAttempt.responses = freshAttemptResponses
            
            if let idea = currentIdea {
                reviewManager.addMistakesToQueue(from: freshAttempt, test: test, idea: idea)
            }
            
            // Mark review items as completed if answered correctly
            let reviewResponses = attempt.responses.filter { response in
                test.questions.first { $0.id == response.questionId }?.orderIndex ?? 0 >= freshQuestions.count
            }
            
            var completedItems: [ReviewQueueItem] = []
            for (index, response) in reviewResponses.enumerated() {
                if response.isCorrect && index < reviewQueueItems.count {
                    completedItems.append(reviewQueueItems[index])
                }
            }
            
            reviewManager.markItemsAsCompleted(completedItems)
        }
        
        // Show results
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            currentView = .results
        }
    }
}

// MARK: - Review Test Results View
private struct ReviewTestResultsView: View {
    let attempt: TestAttempt
    let test: Test
    let book: Book
    let onContinue: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                // Score summary
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: scoreIcon)
                        .font(.system(size: 64))
                        .foregroundColor(scoreColor)
                        .padding(.top, DS.Spacing.xl)
                    
                    Text("Practice Complete!")
                        .font(DS.Typography.largeTitle)
                        .foregroundColor(DS.Colors.black)
                    
                    Text("\(correctCount) of \(totalQuestions) Correct")
                        .font(DS.Typography.headline)
                        .foregroundColor(DS.Colors.black)
                    
                    Text("\(percentage)% Accuracy")
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Colors.secondaryText)
                }
                
                // Mistake summary
                if incorrectCount > 0 {
                    mistakeSummary
                }
                
                Spacer()
                
                // Continue button
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
    
    private var totalQuestions: Int {
        attempt.responses.count
    }
    
    private var correctCount: Int {
        attempt.responses.filter { $0.isCorrect }.count
    }
    
    private var incorrectCount: Int {
        totalQuestions - correctCount
    }
    
    private var percentage: Int {
        guard totalQuestions > 0 else { return 0 }
        return Int((Double(correctCount) / Double(totalQuestions)) * 100)
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
        case 90...100: return .yellow
        case 70..<90: return .green
        case 50..<70: return DS.Colors.black
        default: return .orange
        }
    }
    
    private var mistakeSummary: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Mistakes Added to Review Queue")
                .font(DS.Typography.bodyBold)
                .foregroundColor(DS.Colors.black)
            
            Text("\(incorrectCount) question\(incorrectCount == 1 ? "" : "s") will appear in future review sessions")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)
            
            // Show current queue status
            let queueManager = ReviewQueueManager(modelContext: modelContext)
            let stats = queueManager.getQueueStatistics(for: book.title)
            
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.orange)
                Text("Total in queue: \(stats.totalMCQs + stats.totalOpenEnded)")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
            }
        }
        .padding(DS.Spacing.lg)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, DS.Spacing.lg)
    }
}
