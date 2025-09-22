import SwiftUI
import SwiftData

struct DailyPracticeWithReviewView: View {
    let book: Book
    let openAIService: OpenAIService
    // When provided, identifies the specific review-only lesson (e.g., 16, 17, ...)
    // Used to persist and reload the exact set of questions like routine lessons.
    let selectedLesson: GeneratedLesson?
    let onPracticeComplete: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isGenerating = true
    @State private var freshQuestions: [Question] = []
    @State private var reviewQuestions: [Question] = []
    @State private var reviewQueueItems: [ReviewQueueItem] = []
    @State private var reviewQuestionToQueueItem: [UUID: ReviewQueueItem] = [:]
    @State private var currentIdea: Idea?
    @State private var combinedTest: Test?
    @State private var errorMessage: String?
    @State private var showingTest = false
    @State private var showingPrimer = false
    @State private var showingAttempts = false
    @State private var completedAttempt: TestAttempt?
    @State private var currentView: PracticeFlowState = .none
    @State private var shouldShowStreakToday: Bool = false
    
    enum PracticeFlowState {
        case none
        case results
        case streak
    }
    
    private func getIdeaTitle(ideaId: String) -> String? {
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { $0.id == ideaId }
        )
        do {
            let results = try modelContext.fetch(descriptor)
            return results.first?.title
        } catch {
            return nil
        }
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
    
    private var curveballService: CurveballService {
        CurveballService(modelContext: modelContext)
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
                            if shouldShowStreakToday {
                                withAnimation { currentView = .streak }
                            } else {
                                currentView = .none
                                onPracticeComplete?()
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
            
            // Practice Breakdown — show idea composition like routine lessons
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text("Today's Session")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)

                // Idea composition (grouped counts)
                let all = reviewQuestions
                let grouped = Dictionary(grouping: all, by: { $0.ideaId })
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(Array(grouped.keys), id: \.self) { ideaId in
                        let count = grouped[ideaId]?.count ?? 0
                        let title = getIdeaTitle(ideaId: ideaId) ?? "Idea"
                        HStack {
                            Text(title)
                                .font(DS.Typography.body)
                                .foregroundColor(DS.Colors.black)
                            Spacer()
                            Text("\(count) question\(count == 1 ? "" : "s")")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                        }
                    }
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
                
                if let idea = currentIdea, idea.id != "review_session" {
                    Button("Previous Attempts") {
                        showingAttempts = true
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
        .sheet(isPresented: $showingAttempts) {
            if let idea = currentIdea { IdeaResponsesView(idea: idea) }
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
                let queueStats = reviewQueueManager.getQueueStatistics(bookId: book.id.uuidString)
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
    
    // Unique key for persisting a specific review-only lesson session
    private var reviewSessionKey: String {
        if let n = selectedLesson?.lessonNumber { return "review_session_\(n)" }
        return "review_session"
    }

    private func generateDailyPractice() async {
        isGenerating = true
        errorMessage = nil
        
        do {
            // Ensure due curveballs and spacedfollowups for this book are queued before selecting
            let bookId = book.id.uuidString
            curveballService.ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: book.title)
            let spacedService = SpacedFollowUpService(modelContext: modelContext)
            spacedService.ensureSpacedFollowUpsQueuedIfDue(bookId: bookId, bookTitle: book.title)
            
            // If we're attached to a numbered review-only lesson, try to reuse a persisted session first
            if selectedLesson != nil {
                if let existing = try await fetchExistingSession(for: reviewSessionKey, type: "review_practice"),
                   let test = existing.test,
                   (test.questions ?? []).isEmpty == false {
                    // Rehydrate state for UI
                    await MainActor.run {
                        self.currentIdea = createDailyPracticeIdea()
                        self.combinedTest = test
                        self.reviewQuestions = test.orderedQuestions
                        // Rebuild mapping from persisted sourceQueueItemId
                        var map: [UUID: ReviewQueueItem] = [:]
                        for q in test.orderedQuestions {
                            if let src = q.sourceQueueItemId {
                                let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == src })
                                if let item = try? modelContext.fetch(fetch).first {
                                    map[q.id] = item
                                }
                            }
                        }
                        self.reviewQuestionToQueueItem = map
                        self.isGenerating = false
                    }
                    return
                }
            }
            // For pure review sessions, we only need review questions
            // 1. Get review items from queue for this specific book — review-only sessions want 6 MCQ + 2 OEQ
            let (mcqItems, openEndedItems) = reviewQueueManager.getDailyReviewItems(bookId: book.id.uuidString, mcqCap: 6, openCap: 2)
            reviewQueueItems = mcqItems + openEndedItems
            
            print("🔄 REVIEW SESSION: Found \(reviewQueueItems.count) items in queue (\(mcqItems.count) MCQ, \(openEndedItems.count) Open-ended)")
            
            // 2. Generate similar questions for review items
            if !reviewQueueItems.isEmpty {
                let generated = try await testGenerationService.generateReviewQuestionsFromQueue(reviewQueueItems)
                // Pair queue items with generated questions
                var pairs = Array(zip(reviewQueueItems, generated))
                // Sort by question difficulty while keeping pairs intact
                pairs.sort { lhs, rhs in
                    lhs.1.difficulty.pointValue < rhs.1.difficulty.pointValue
                }
                // Unzip back and build mapping
                reviewQueueItems = pairs.map { $0.0 }
                reviewQuestions = pairs.map { $0.1 }
                reviewQuestionToQueueItem = Dictionary(uniqueKeysWithValues: pairs.map { ($0.1.id, $0.0) })
                
                let easyCount = reviewQuestions.filter { $0.difficulty == .easy }.count
                let mediumCount = reviewQuestions.filter { $0.difficulty == .medium }.count
                let hardCount = reviewQuestions.filter { $0.difficulty == .hard }.count
                print("🔄 REVIEW SESSION: Generated \(reviewQuestions.count) review questions (Easy: \(easyCount), Medium: \(mediumCount), Hard: \(hardCount))")
            }
            
            // 3. Create and optionally persist test with only review questions
            if !reviewQuestions.isEmpty {
                // Create a dummy idea for the review session
                currentIdea = Idea(
                    id: "review_session",
                    title: "Review Practice",
                    description: "Mixed review from multiple ideas",
                    bookTitle: book.title,
                    depthTarget: 1
                )
                
                if selectedLesson != nil {
                    // Persist like routine lessons so revisits reload instantly
                    // Build persisted Test and clone questions while writing sourceQueueItemId for mapping
                    let test = Test(
                        ideaId: currentIdea!.id,
                        ideaTitle: currentIdea!.title,
                        bookTitle: book.title,
                        testType: "daily"
                    )
                    await MainActor.run {
                        self.modelContext.insert(test)
                    }
                    
                    // Build pairs aligning reviewQuestions with queue items for mapping
                    var mapping: [UUID: ReviewQueueItem] = [:]
                    var cloned: [Question] = []
                    for (index, q) in reviewQuestions.enumerated() {
                        // Try match by existing sourceQueueItemId first
                        var srcItem: ReviewQueueItem? = nil
                        if let sid = q.sourceQueueItemId {
                            let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == sid })
                            srcItem = try? modelContext.fetch(fetch).first
                        }
                        if srcItem == nil {
                            // Fallback: best-effort by ideaId and difficulty
                            srcItem = reviewQueueItems.first { $0.ideaId == q.ideaId }
                        }
                        let nq = Question(
                            ideaId: q.ideaId,
                            type: q.type,
                            difficulty: q.difficulty,
                            bloomCategory: q.bloomCategory,
                            questionText: q.questionText,
                            options: q.options,
                            correctAnswers: q.correctAnswers,
                            orderIndex: index,
                            isCurveball: q.isCurveball,
                            isSpacedFollowUp: q.isSpacedFollowUp,
                            sourceQueueItemId: srcItem?.id
                        )
                        cloned.append(nq)
                        if let src = srcItem { mapping[nq.id] = src }
                    }
                    reviewQuestionToQueueItem = mapping
                    
                    try await MainActor.run {
                        for q in cloned {
                            q.test = test
                            if test.questions == nil { test.questions = [] }
                            test.questions?.append(q)
                            self.modelContext.insert(q)
                        }
                        try self.modelContext.save()
                        // Create PracticeSession keyed to this review lesson number
                        let session = PracticeSession(
                            ideaId: reviewSessionKey,
                            bookId: book.id.uuidString,
                            type: "review_practice",
                            status: "ready",
                            configVersion: 1
                        )
                        session.test = test
                        self.modelContext.insert(session)
                        try self.modelContext.save()
                        self.combinedTest = test
                        self.reviewQuestions = cloned
                    }
                    print("🔄 REVIEW SESSION: Persisted test with \(reviewQuestions.count) questions for \(reviewSessionKey)")
                } else {
                    // Ephemeral review practice (from menu): do not persist
                    combinedTest = createCombinedTest(fresh: [], review: reviewQuestions)
                    print("🔄 REVIEW SESSION: Created test with \(reviewQuestions.count) questions")
                }
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
    
    // MARK: - Session helpers (review-only)
    private func fetchExistingSession(for ideaId: String, type: String) async throws -> PracticeSession? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PracticeSession>(
                predicate: #Predicate { s in
                    s.ideaId == ideaId && s.type == type && s.status == "ready"
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let results = try self.modelContext.fetch(descriptor)
            return results.first
        }
    }
    
    private func getNextUnlearnedIdea() -> Idea? {
        // Find the first idea that hasn't been tested yet
        let targetBookTitle = book.title
        // First fetch all ideas for this book, then filter by mastery in code
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.bookTitle == targetBookTitle
            },
            sortBy: [SortDescriptor(\.id)]
        )
        
        do {
            let ideasForBook = try modelContext.fetch(descriptor)
            let unlearned = ideasForBook.first { $0.masteryLevel == 0 }
            return unlearned
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
    
    private func handleTestCompletion(_ attempt: TestAttempt, _ didIncrementStreak: Bool) {
        completedAttempt = attempt
        showingTest = false
        shouldShowStreakToday = didIncrementStreak
        
        // Record mistakes to review queue
        if let test = combinedTest {
            let reviewManager = ReviewQueueManager(modelContext: modelContext)
            
            // Only add mistakes from fresh questions to queue
            let freshAttemptResponses = (attempt.responses ?? []).filter { response in
                (test.questions ?? []).first { $0.id == response.questionId }?.orderIndex ?? 0 < freshQuestions.count
            }
            
            // Create a fresh attempt for recording purposes
            let freshAttempt = TestAttempt(testId: test.id)
            freshAttempt.responses = freshAttemptResponses
            
            if let idea = currentIdea {
                reviewManager.addMistakesToQueue(from: freshAttempt, test: test, idea: idea)
            }
            
            // Mark review items as completed if answered correctly
            let reviewResponses = (attempt.responses ?? []).filter { response in
                (test.questions ?? []).first { $0.id == response.questionId }?.orderIndex ?? 0 >= freshQuestions.count
            }
            
            var completedItems: [ReviewQueueItem] = []
            for response in reviewResponses {
                if response.isCorrect {
                    if let item = reviewQuestionToQueueItem[response.questionId] {
                        completedItems.append(item)
                    } else if let q = (test.questions ?? []).first(where: { $0.id == response.questionId }), let srcId = q.sourceQueueItemId {
                        let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == srcId })
                        if let item = try? modelContext.fetch(fetch).first { completedItems.append(item) }
                    }
                }
            }
            
            reviewManager.markItemsAsCompleted(completedItems)

            // If any completed item was a passed curveball or spacedfollowup, mark coverage+mastery
            let bookId = book.id.uuidString
            for response in reviewResponses {
                var curveItem: ReviewQueueItem?
                if let item = reviewQuestionToQueueItem[response.questionId] { curveItem = item }
                else if let q = (test.questions ?? []).first(where: { $0.id == response.questionId }), let srcId = q.sourceQueueItemId {
                    let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == srcId })
                    curveItem = try? modelContext.fetch(fetch).first
                }
                guard let item = curveItem else { continue }
                if item.isCurveball {
                    let curveService = CurveballService(modelContext: modelContext)
                    if response.isCorrect {
                        // Passed: mark result and promote mastery
                        curveService.markCurveballResult(ideaId: item.ideaId, bookId: bookId, passed: true)
                        let targetId = item.ideaId
                        let ideaDescriptor = FetchDescriptor<Idea>(
                            predicate: #Predicate<Idea> { idea in
                                idea.id == targetId
                            }
                        )
                        if let masteredIdea = try? modelContext.fetch(ideaDescriptor).first {
                            masteredIdea.masteryLevel = 3
                        }
                    } else {
                        // Failed: remove current curveball from queue and reschedule for later
                        item.isCompleted = true
                        curveService.markCurveballResult(ideaId: item.ideaId, bookId: bookId, passed: false)
                    }
                } else if item.isSpacedFollowUp {
                    let targetIdeaId = item.ideaId
                    let targetBookId = bookId
                    let covDesc = FetchDescriptor<IdeaCoverage>(
                        predicate: #Predicate<IdeaCoverage> { c in
                            c.ideaId == targetIdeaId && c.bookId == targetBookId
                        }
                    )
                    if let cov = try? modelContext.fetch(covDesc).first {
                        if response.isCorrect {
                            cov.spacedFollowUpPassedAt = Date()
                            cov.curveballDueDate = Calendar.current.date(byAdding: .day, value: SpacedFollowUpConfig.curveballAfterPassDays, to: Date())
                        } else {
                            cov.spacedFollowUpDueDate = Calendar.current.date(byAdding: .day, value: SpacedFollowUpConfig.retryDelayDays, to: Date())
                        }
                        try? modelContext.save()
                    }
                }
            }
            try? modelContext.save()
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
        (attempt.responses ?? []).count
    }
    
    private var correctCount: Int {
        (attempt.responses ?? []).filter { $0.isCorrect }.count
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
            let stats = queueManager.getQueueStatistics(bookId: book.id.uuidString)
            
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
