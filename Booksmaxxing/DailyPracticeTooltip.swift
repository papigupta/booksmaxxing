import SwiftUI
import SwiftData

@MainActor
struct DailyPracticeTooltip: View {
    let book: Book
    let openAIService: OpenAIService
    let lesson: GeneratedLesson
    let fillColor: Color
    let strokeColor: Color
    let onPracticeComplete: (() -> Void)?
    
    init(
        book: Book,
        openAIService: OpenAIService,
        lesson: GeneratedLesson,
        fillColor: Color,
        strokeColor: Color,
        onPracticeComplete: (() -> Void)? = nil
    ) {
        self.book = book
        self.openAIService = openAIService
        self.lesson = lesson
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.onPracticeComplete = onPracticeComplete
    }
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isGenerating = true
    @State private var generatedTest: Test?
    @State private var activePracticeSession: PracticeSession?
    @State private var activeAttempt: TestAttempt?
    @State private var errorMessage: String?
    @State private var showingTest = false
    @State private var showingPrimer = false
    @State private var showingAttempts = false
    @State private var completedAttempt: TestAttempt?
    @State private var currentView: PracticeFlowState = .none
    // Map cloned review question IDs -> source queue items
    @State private var reviewQuestionToQueueItem: [UUID: ReviewQueueItem] = [:]
    // Celebration sequencing
    @State private var celebrationQueue: [Idea] = []
    @State private var currentCelebrationIdea: Idea? = nil
    @State private var sessionBCal: Int = 0
    @State private var todayBCalTotal: Int = 0
    @State private var sessionCorrect: Int = 0
    @State private var sessionTotal: Int = 0
    @State private var todayCorrect: Int = 0
    @State private var todayTotal: Int = 0
    @State private var sessionPauses: Int = 0
    @State private var todayPauses: Int = 0
    @State private var todayAttentionPercent: Int = 0
    @State private var hasPrefetchedExplanations = false
    @State private var showingOverflow: Bool = false
    
    enum PracticeFlowState {
        case none
        case streak
        case bcal
        case celebration
    }

    private enum PracticeSessionStatus {
        static let ready = "ready"
        static let generating = "generating"
        static let inProgress = "in_progress"
        static let paused = "paused"
        static let completed = "completed"
        static let error = "error"
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
        if let idea = (book.ideas ?? []).first(where: { $0.id == lesson.primaryIdeaId }) {
            return idea
        }

        return Idea(
            id: lesson.primaryIdeaId,
            title: lesson.primaryIdeaTitle,
            description: "Lesson \(lesson.lessonNumber) practice",
            bookTitle: book.title,
            depthTarget: 3
        )
    }
    
    var body: some View {
        let tokens = themeManager.currentTokens(for: colorScheme)
        return VStack(alignment: .leading, spacing: TooltipLayout.sectionSpacing) {
            questionMixSection(tokens: tokens)

            actionRow
        }
        .padding(.horizontal, TooltipLayout.horizontalPadding)
        .padding(.vertical, TooltipLayout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tooltipBackground)
        .overlay(tooltipBorder)
        .clipShape(RoundedRectangle(cornerRadius: TooltipLayout.cornerRadius, style: .continuous))
        .task {
            await generatePractice()
        }
        .onAppear {
            Task { await themeManager.activateTheme(for: book) }
        }
        .onChange(of: generatedTest?.id) { _, _ in
            if let test = generatedTest {
                startWhyPrefetch(for: test)
            }
        }
        .confirmationDialog("Options", isPresented: $showingOverflow, titleVisibility: .visible) {
            if ideaForTest.id != "daily_practice" {
                Button("Previous Attempts") { showingAttempts = true }
            }
            Button("Brush Up with Primer") { showingPrimer = true }
            Button("Generate New Questions") { Task { await refreshPractice() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: ideaForTest, openAIService: openAIService)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAttempts) {
            IdeaResponsesView(idea: ideaForTest)
        }
        .fullScreenCover(isPresented: $showingTest) {
            if let test = generatedTest {
                TestView(
                    idea: ideaForTest,
                    test: test,
                    openAIService: openAIService,
                    onCompletion: handleTestCompletion,
                    onSubmitted: { _ in },
                    onExit: { handlePracticeExit() },
                    existingAttempt: activeAttempt
                )
            }
        }
        .fullScreenCover(isPresented: .constant(currentView != .none)) {
            if currentView == .streak {
                StreakView(onContinue: {
                    print("DEBUG: ✅ Streak onContinue tapped")
                    withAnimation { currentView = .bcal }
                })
            } else if currentView == .bcal {
                BrainCaloriesView(
                    sessionBCal: sessionBCal,
                    todayBCalTotal: todayBCalTotal,
                    sessionCorrect: sessionCorrect,
                    sessionTotal: sessionTotal,
                    todayCorrect: todayCorrect,
                    todayTotal: todayTotal,
                    goalAccuracyPercent: 80,
                    sessionPauses: sessionPauses,
                    todayPauses: todayPauses,
                    todayAttentionPercent: todayAttentionPercent,
                    onContinue: {
                        if !celebrationQueue.isEmpty {
                            currentCelebrationIdea = celebrationQueue.removeFirst()
                            withAnimation { currentView = .celebration }
                        } else {
                            currentCelebrationIdea = nil
                            currentView = .none
                            if let onComplete = onPracticeComplete { onComplete() }
                            else { print("DEBUG: ❌ onPracticeComplete callback is nil!") }
                        }
                    }
                )
            } else if currentView == .celebration {
                if let idea = currentCelebrationIdea {
                    CelebrationView(
                        idea: idea,
                        userResponse: "",
                        level: 3,
                        starScore: 3,
                        openAIService: openAIService,
                        onContinue: {
                            if !celebrationQueue.isEmpty {
                                currentCelebrationIdea = celebrationQueue.removeFirst()
                            } else {
                                currentCelebrationIdea = nil
                                currentView = .none
                                if let onComplete = onPracticeComplete { onComplete() }
                                else { print("DEBUG: ❌ onPracticeComplete callback is nil!") }
                            }
                        }
                    )
                }
            } else {
                let tokens = themeManager.currentTokens(for: colorScheme)
                tokens.surfaceVariant
                    .overlay(
                        Text("DEBUG: Unexpected state: \(currentView)")
                            .foregroundColor(tokens.onSurface)
                    )
            }
        }
    }

    // MARK: - Views
    private func questionMixSection(tokens: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: TooltipLayout.mixSpacing) {
            Text("Question Mix")
                .font(DS.Typography.fraunces(size: 14, weight: .semibold))
                .tracking(DS.Typography.tightTracking(for: 14))
                .foregroundColor(tokens.onSurface.opacity(0.8))

            if let error = errorMessage {
                tooltipErrorRow(error, tokens: tokens)
            } else if isGenerating {
                placeholderRows(tokens: tokens)
            } else if let test = generatedTest {
                questionRows(for: test, tokens: tokens)
            } else {
                placeholderRows(tokens: tokens)
            }
        }
    }

    private var actionRow: some View {
        let ctaTitle = lesson.isCompleted ? "Retry Lesson" : "Start Practicing"
        return HStack(spacing: TooltipLayout.buttonSpacing) {
            Button(action: { startPracticeSession() }) {
                Text(ctaTitle)
                    .font(DS.Typography.fraunces(size: 16, weight: .semibold))
                    .tracking(DS.Typography.tightTracking(for: 16))
                    .frame(maxWidth: .infinity)
            }
            .dsPalettePrimaryButton()
            .disabled(generatedTest == nil || isGenerating)

            Button(action: { showingOverflow = true }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .frame(width: TooltipLayout.kebabButtonSize)
            .dsPalettePrimaryButton(horizontalPadding: 0, verticalPadding: 0, minHeight: TooltipLayout.primaryButtonHeight)
            .accessibilityLabel("More options")
        }
    }

    private var tooltipBackground: some View {
        RoundedRectangle(cornerRadius: TooltipLayout.cornerRadius, style: .continuous)
            .fill(fillColor)
    }

    private var tooltipBorder: some View {
        RoundedRectangle(cornerRadius: TooltipLayout.cornerRadius, style: .continuous)
            .stroke(strokeColor, lineWidth: 1.5)
    }

    private func questionRows(for test: Test, tokens: ThemeTokens) -> some View {
        let questionsByIdea = Dictionary(grouping: (test.questions ?? [])) { $0.ideaId }
        let textColor = tokens.onSurface
        let subtle = textColor.opacity(0.6)

        let orderedIdeas: [(id: String, title: String, count: Int)] = questionsByIdea.compactMap { ideaId, questions in
            let title = getIdeaTitle(for: ideaId) ?? ideaId
            return (ideaId, title, questions.count)
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.count > rhs.count
        }

        return VStack(spacing: TooltipLayout.rowSpacing) {
            ForEach(orderedIdeas, id: \.id) { entry in
                questionRow(title: entry.title, count: entry.count, textColor: textColor, secondaryColor: subtle)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func questionRow(title: String, count: Int, textColor: Color, secondaryColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Typography.fraunces(size: 14, weight: .semibold))
                .tracking(DS.Typography.tightTracking(for: 14))
                .foregroundColor(textColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("\(count)")
                    .font(DS.Typography.fraunces(size: 14, weight: .semibold))
                    .tracking(DS.Typography.tightTracking(for: 14))
                    .foregroundColor(textColor)
                Text("questions")
                    .font(DS.Typography.fraunces(size: 14, weight: .light))
                    .tracking(DS.Typography.tightTracking(for: 14))
                    .foregroundColor(secondaryColor)
            }
        }
    }

    private func tooltipErrorRow(_ error: String, tokens: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(error)
                .font(DS.Typography.caption)
                .foregroundColor(tokens.onSurface)
            Button("Try Again") {
                Task { await generatePractice() }
            }
            .font(DS.Typography.captionBold)
        }
    }

    private func placeholderRows(tokens: ThemeTokens) -> some View {
        VStack(spacing: TooltipLayout.rowSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.onSurface.opacity(0.08))
                    .frame(height: 12)
                    .redacted(reason: .placeholder)
            }
        }
    }

    private func startWhyPrefetch(for test: Test) {
        guard !hasPrefetchedExplanations else { return }
        hasPrefetchedExplanations = true

        let evaluationService = TestEvaluationService(openAI: openAIService, modelContext: modelContext)
        let idea = ideaForTest

        Task(priority: .background) {
            let questions = await MainActor.run { test.orderedQuestions }
            for question in questions where question.type != .openEnded {
                await evaluationService.prefetchWhyIfNeeded(for: question, idea: idea)
            }
        }
    }
    
    // MARK: - Actions
    
    private func generatePractice() async {
        isGenerating = true
        errorMessage = nil

        do {
            let test: Test
            
            var persistedSession: PracticeSession?

            let currentLesson = lesson
            print("DEBUG: Generating practice test for lesson \(currentLesson.lessonNumber)")
            // Proactively prewarm ONLY the initial 8 for the next lesson while user works on this lesson.
            let next = currentLesson.lessonNumber + 1
            Task {
                let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
                prefetcher.prewarmInitialQuestions(book: book, lessonNumber: next)
                print("PREFETCH: Prewarmed initial 8 for upcoming lesson \(next) from generatePractice()")
            }
            
            // Get the primary idea for this lesson
            guard let primaryIdea = (book.ideas ?? []).first(where: { $0.id == currentLesson.primaryIdeaId }) else {
                throw NSError(domain: "LessonGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find idea for lesson \(currentLesson.lessonNumber)"])
            }

            // 0) Check for any existing session (ready/generating/error) to honor prefetch state
            if let existingSession = try await fetchSessionAnyStatus(for: primaryIdea.id, type: "lesson_practice") {
                if let existingTest = existingSession.test,
                   (existingTest.questions ?? []).count >= 8,
                   existingSession.status == PracticeSessionStatus.ready {
                    print("DEBUG: Found READY session with \((existingTest.questions ?? []).count) questions")
                    await MainActor.run {
                        self.applyLoadedSession(test: existingTest, session: existingSession)
                    }
                    return
                } else if let existingTest = existingSession.test,
                          (existingTest.questions ?? []).count >= 8,
                          (existingSession.status == PracticeSessionStatus.inProgress || existingSession.status == PracticeSessionStatus.paused) {
                    let stateLabel = existingSession.status == PracticeSessionStatus.inProgress ? "IN_PROGRESS" : "PAUSED"
                    print("DEBUG: Found \(stateLabel) session with \((existingTest.questions ?? []).count) questions")
                    await MainActor.run {
                        self.applyLoadedSession(test: existingTest, session: existingSession)
                    }
                    return
                } else if existingSession.status == PracticeSessionStatus.generating {
                        let cutoff = Date().addingTimeInterval(-PracticePrefetcher.staleInterval)
                        if existingSession.updatedAt < cutoff {
                            print("DEBUG: Found stale GENERATING session; deleting and regenerating inline")
                            await MainActor.run {
                                self.modelContext.delete(existingSession)
                                try? self.modelContext.save()
                            }
                        } else {
                            print("DEBUG: Found GENERATING session; waiting for readiness…")
                            // Poll for up to ~40 seconds (batching can take longer)
                            var attempts = 0
                            while attempts < 40 {
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                if let refreshed = try await fetchSessionAnyStatus(for: primaryIdea.id, type: "lesson_practice") {
                                    if refreshed.status == PracticeSessionStatus.ready,
                                       let readyTest = refreshed.test,
                                       (readyTest.questions ?? []).count >= 8 {
                                        await MainActor.run {
                                            self.applyLoadedSession(test: readyTest, session: refreshed)
                                        }
                                        return
                                    } else if refreshed.status == PracticeSessionStatus.error {
                                        let msg = String(data: refreshed.configData ?? Data(), encoding: .utf8) ?? "Failed to prepare session."
                                        await MainActor.run {
                                            self.errorMessage = msg
                                            self.isGenerating = false
                                        }
                                        return
                                    }
                                }
                                attempts += 1
                            }
                            // Timed out; proceed to generate inline as fallback
                            print("DEBUG: GENERATING session timed out; generating inline…")
                        }
                    } else if existingSession.status == PracticeSessionStatus.error {
                        print("DEBUG: Found ERROR session; deleting and regenerating inline")
                        await MainActor.run {
                            self.modelContext.delete(existingSession)
                            try? self.modelContext.save()
                        }
                    }
                }

                // 1) Try to reuse an existing practice session (persisted mixed test)
                if let existingSession = try await fetchExistingSession(for: primaryIdea.id, type: "lesson_practice"),
                   let existingTest = existingSession.test,
                   (existingTest.questions ?? []).count >= 8 {
                    print("DEBUG: Reusing existing practice session with \((existingTest.questions ?? []).count) questions")
                    await MainActor.run {
                        self.applyLoadedSession(test: existingTest, session: existingSession)
                    }
                    return
                }
                
                print("DEBUG: Generating test for idea: \(primaryIdea.title)")
                
                // Generate fresh questions for the primary idea
                let freshTest = try await testGenerationService.generateTest(
                    for: primaryIdea,
                    testType: "initial"
                )
                
                // Ensure any due curveballs and spacedfollowups are queued for this book
                let curveballService = CurveballService(modelContext: modelContext)
                curveballService.ensureCurveballsQueuedIfDue(bookId: book.id.uuidString, bookTitle: book.title)
                let spacedService = SpacedFollowUpService(modelContext: modelContext)
                spacedService.ensureSpacedFollowUpsQueuedIfDue(bookId: book.id.uuidString, bookTitle: book.title)

                // Get review questions from the queue (max 3 MCQ + 1 OEQ = 4 total) for this book only
                let reviewManager = ReviewQueueManager(modelContext: modelContext)
                let (mcqItems, openEndedItems) = reviewManager.getDailyReviewItems(
                    bookId: book.id.uuidString,
                    bookTitle: book.title
                )
                let allReviewItems = mcqItems + openEndedItems // Already limited to 3 MCQ + 1 OEQ
                
                // Use orderedQuestions to preserve the fixed internal sequence (Q6/Q8 invariants)
                let freshQuestions = freshTest.orderedQuestions

                // Partition by difficulty while preserving relative order within each group
                let easyFresh = freshQuestions.filter { $0.difficulty == .easy }
                let mediumFresh = freshQuestions.filter { $0.difficulty == .medium }
                var hardFresh = freshQuestions.filter { $0.difficulty == .hard }

                // Ensure the single open-ended question (now Q8) is at the end of the hard bucket
                if let idx = hardFresh.firstIndex(where: { $0.type == .openEnded }) {
                    let openEnded = hardFresh.remove(at: idx)
                    hardFresh.append(openEnded)
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
                test.idea = primaryIdea
                
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
                        isCurveball: q.isCurveball,
                        isSpacedFollowUp: q.isSpacedFollowUp,
                        sourceQueueItemId: q.sourceQueueItemId
                    )
                    // Preserve HowWield payload if present for UI/analytics
                    if let hw = q.howWieldPayload { cloned.howWieldPayload = hw }
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
                        if test.questions == nil { test.questions = [] }
                        test.questions?.append(q)
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
                    persistedSession = session
                }

                print("DEBUG: Generated and saved mixed test with \((test.questions ?? []).count) questions (\(freshTest.orderedQuestions.count) fresh + \(combined.count - freshTest.orderedQuestions.count) review)")
            await MainActor.run {
                self.applyLoadedSession(test: test, session: persistedSession)
            }
        } catch {
            print("ERROR: Failed to generate practice: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }

    @MainActor
    private func applyLoadedSession(test: Test, session: PracticeSession?) {
        self.activePracticeSession = session
        self.generatedTest = test
        self.isGenerating = false
        self.hasPrefetchedExplanations = false
        restoreAttemptIfAvailable(for: test)
    }

    @MainActor
    private func restoreAttemptIfAvailable(for test: Test) {
        guard let attempt = findIncompleteAttempt(for: test) else {
            self.activeAttempt = nil
            return
        }
        self.activeAttempt = attempt
        if activePracticeSession?.status == PracticeSessionStatus.inProgress {
            self.showingTest = true
        }
    }

    @MainActor
    private func findIncompleteAttempt(for test: Test) -> TestAttempt? {
        if let attempt = test.attempts?.last(where: { !$0.isComplete }) {
            return attempt
        }

        let targetTestId = test.id
        let descriptor = FetchDescriptor<TestAttempt>(
            predicate: #Predicate<TestAttempt> { attempt in
                attempt.testId == targetTestId
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first(where: { !$0.isComplete })
    }

    @MainActor
    private func startPracticeSession() {
        guard let test = generatedTest else { return }
        guard let attempt = fetchOrCreateActiveAttempt(for: test) else { return }
        activeAttempt = attempt
        showingTest = true
    }

    @MainActor
    private func fetchOrCreateActiveAttempt(for test: Test) -> TestAttempt? {
        if let attempt = findIncompleteAttempt(for: test) {
            updateCurrentSessionStatus(PracticeSessionStatus.inProgress)
            return attempt
        }

        let attempt = TestAttempt(testId: test.id)
        attempt.test = test
        if test.attempts == nil { test.attempts = [] }
        test.attempts?.append(attempt)
        modelContext.insert(attempt)
        try? modelContext.save()
        updateCurrentSessionStatus(PracticeSessionStatus.inProgress)
        return attempt
    }

    @MainActor
    private func handlePracticeExit() {
        showingTest = false
        updateCurrentSessionStatus(PracticeSessionStatus.paused)
    }

    @MainActor
    private func updateCurrentSessionStatus(_ status: String) {
        guard let session = activePracticeSession else { return }
        session.status = status
        session.updatedAt = Date()
        try? modelContext.save()
    }

    private func handleTestCompletion(_ attempt: TestAttempt, _ didIncrementStreak: Bool) {
        completedAttempt = attempt
        showingTest = false
        activeAttempt = nil
        updateCurrentSessionStatus(PracticeSessionStatus.completed)
        
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
            print("DEBUG: Saved attempt with \((attempt.responses ?? []).count) responses")
        } else {
            print("DEBUG: Failed to fetch responses for attempt \(attempt.id)")
        }
        
        // Add NEW mistakes to review queue (only from fresh questions)
        if let test = generatedTest, let primaryIdea = (book.ideas ?? []).first(where: { $0.id == lesson.primaryIdeaId }) {
            let reviewManager = ReviewQueueManager(modelContext: modelContext)
            
            // Determine how many fresh questions we had (they come first in the ordered list)
            // Fresh questions are from the primary idea
            let freshQuestionCount = (test.questions ?? []).filter { $0.ideaId == primaryIdea.id }.count
            
            // Only add mistakes from fresh questions to the queue
            let freshResponses = (attempt.responses ?? []).filter { response in
                if let question = (test.questions ?? []).first(where: { $0.id == response.questionId }) {
                    // Check if this is a fresh question (from the primary idea)
                    return question.ideaId == primaryIdea.id && (response.isCorrect == false)
                }
                return false
            }
            
            // Add mistakes directly from responses (no temp attempt to avoid SwiftData crashes)
            reviewManager.addMistakesToQueue(fromResponses: freshResponses, test: test, idea: primaryIdea)
            
            // Mark review questions as completed if answered correctly
            let reviewResponses = (attempt.responses ?? []).filter { response in
                if let question = (test.questions ?? []).first(where: { $0.id == response.questionId }) {
                    return question.orderIndex >= freshQuestionCount
                }
                return false
            }
            
            var completedItems: [ReviewQueueItem] = []
            for response in reviewResponses where response.isCorrect {
                if let item = reviewQuestionToQueueItem[response.questionId] {
                    completedItems.append(item)
                } else if let q = (test.questions ?? []).first(where: { $0.id == response.questionId }), let srcId = q.sourceQueueItemId {
                    let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == srcId })
                    if let item = try? modelContext.fetch(fetch).first { completedItems.append(item) }
                }
            }
            reviewManager.markItemsAsCompleted(completedItems)

            // Handle curveball and spacedfollowup pass/fail, then mastery
            let curveService = CurveballService(modelContext: modelContext)
            for response in reviewResponses {
                var mapped: ReviewQueueItem?
                if let m = reviewQuestionToQueueItem[response.questionId] { mapped = m }
                else if let q = (test.questions ?? []).first(where: { $0.id == response.questionId }), let srcId = q.sourceQueueItemId {
                    let fetch = FetchDescriptor<ReviewQueueItem>(predicate: #Predicate<ReviewQueueItem> { $0.id == srcId })
                    mapped = try? modelContext.fetch(fetch).first
                }
                guard let item = mapped else { continue }
                if item.isCurveball {
                    if response.isCorrect {
                        curveService.markCurveballResult(ideaId: item.ideaId, bookId: book.id.uuidString, passed: true)
                    } else {
                        item.isCompleted = true
                        curveService.markCurveballResult(ideaId: item.ideaId, bookId: book.id.uuidString, passed: false)
                    }
                } else if item.isSpacedFollowUp {
                    let targetIdeaId = item.ideaId
                    let targetBookId = book.id.uuidString
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
        }
        
        // Update mastery for the lesson
        print("DEBUG: generatedTest is \(generatedTest != nil ? "not nil" : "nil")")
        print("DEBUG: active lesson is \(lesson.lessonNumber)")
        
        if let test = generatedTest {
            // Pass the fetched responses directly since attempt.responses might not be working
            updateCoverageFromAttempt(attempt: attempt, test: test, lesson: lesson, fetchedResponses: fetchedResponses)
        } else {
            print("DEBUG: WARNING - Cannot update coverage: test or lesson is nil")
        }
        
        // Build mastery celebration queue (ideas newly hitting mastery gate)
        var candidateIdeaIds: Set<String> = []
        if let test = generatedTest {
            let qMap: [UUID: Question] = Dictionary(uniqueKeysWithValues: (test.questions ?? []).map { ($0.id, $0) })
            for response in (attempt.responses ?? []) {
                if let q = qMap[response.questionId] { candidateIdeaIds.insert(q.ideaId) }
            }
        }

        var masteredIdeas: [Idea] = []
        for ideaId in candidateIdeaIds {
            let targetIdeaId = ideaId
            let targetBookId = book.id.uuidString
            let covDesc = FetchDescriptor<IdeaCoverage>(
                predicate: #Predicate<IdeaCoverage> { c in c.ideaId == targetIdeaId && c.bookId == targetBookId }
            )
            let ideaDesc = FetchDescriptor<Idea>(predicate: #Predicate<Idea> { i in i.id == ideaId })
            let coverage = try? modelContext.fetch(covDesc).first
            let ideaObj = try? modelContext.fetch(ideaDesc).first
            if let coverage, let ideaObj, ideaObj.masteryLevel < 3 {
                let hasEight = Set(coverage.coveredCategories).count >= 8
                let passedSPFU = coverage.spacedFollowUpPassedAt != nil
                let passedCurve = coverage.curveballPassed
                if hasEight && passedSPFU && passedCurve {
                    masteredIdeas.append(ideaObj)
                }
            }
        }
        // Order queue by numeric idea id
        celebrationQueue = masteredIdeas.sortedByNumericId()

        // Compute Brain Calories totals and decide flow
        print("DEBUG: Test completed - didIncrementStreak=\(didIncrementStreak)")
        print("DEBUG: Attempt score: \(attempt.score), responses: \((attempt.responses ?? []).count), celebrations queued=\(celebrationQueue.count)")

        // Session BCal stored on attempt by TestView
        let session = attempt.brainCalories
        sessionBCal = session
        let stats = CognitiveStatsService(modelContext: modelContext)
        stats.addBCalToToday(session)
        // Accuracy (feeds the user-facing Clarity metric)
        sessionTotal = (attempt.responses ?? []).count
        sessionCorrect = (attempt.responses ?? []).filter { $0.isCorrect }.count
        stats.addAnswers(correct: sessionCorrect, total: sessionTotal)
        let acc = stats.todayAccuracy()
        todayCorrect = acc.correct
        todayTotal = acc.total
        todayBCalTotal = stats.todayBCalTotal()
        // Attention
        sessionPauses = attempt.attentionPauses
        stats.addAttentionPauses(sessionPauses)
        todayPauses = stats.todayAttentionPauses()
        todayAttentionPercent = stats.todayAttentionPercent()

        if didIncrementStreak {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { currentView = .streak }
            }
        } else {
            withAnimation { currentView = .bcal }
        }
    }
    
    private func updateCoverageFromAttempt(attempt: TestAttempt, test: Test, lesson: GeneratedLesson, fetchedResponses: [QuestionResponse] = []) {
        let bookId = book.id.uuidString
        print("DEBUG: updateCoverageFromAttempt called")
        print("DEBUG: Updating coverage for lesson \(lesson.lessonNumber), book \(bookId)")
        print("DEBUG: Attempt ID: \(attempt.id)")
        print("DEBUG: Attempt has \((attempt.responses ?? []).count) responses")
        print("DEBUG: fetchedResponses has \(fetchedResponses.count) responses")
        print("DEBUG: Test has \((test.questions ?? []).count) questions")
        
        // Use fetched responses if available, otherwise fall back to attempt.responses
        let responsesToUse: [QuestionResponse] = fetchedResponses.isEmpty ? (attempt.responses ?? []) : fetchedResponses
        print("DEBUG: Using \(responsesToUse.count) responses for coverage calculation")
        
        // Debug: Print all responses
        for (index, response) in responsesToUse.enumerated() {
            print("DEBUG: Response \(index): questionId=\(response.questionId), isCorrect=\(response.isCorrect), userAnswer=\(response.userAnswer)")
        }
        
        // Debug: Print all question IDs in the test
        for question in (test.questions ?? []) {
            print("DEBUG: Test question - id: \(question.id), ideaId: '\(question.ideaId)', bloom: \(question.bloomCategory.rawValue)")
        }
        
        // Group responses by idea
        var responsesByIdea: [String: [(questionId: String, isCorrect: Bool, questionText: String, conceptTested: String, bloomCategory: String)]] = [:]
        
        for response in responsesToUse {
            print("DEBUG: Processing response with questionId: \(response.questionId), isCorrect: \(response.isCorrect)")
            if let question = (test.questions ?? []).first(where: { $0.id == response.questionId }) {
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
        
        // Update coverage for each idea + schedule spacedfollowup if eligible
        for (ideaId, responses) in responsesByIdea {
            print("DEBUG: Updating coverage for idea \(ideaId) with \(responses.count) responses")
            coverageService.updateCoverageFromLesson(
                ideaId: ideaId,
                bookId: bookId,
                responses: responses
            )

            // Try to store a substantial-correct source (Medium/Hard MCQ or any OEQ)
            let covFetch = FetchDescriptor<IdeaCoverage>(predicate: #Predicate<IdeaCoverage> { c in c.ideaId == ideaId && c.bookId == bookId })
            if let coverage = try? modelContext.fetch(covFetch).first {
                // Choose best source from today's correct answers: Hard MCQ → Medium MCQ → OEQ
                let qMap: [String: Question] = Dictionary(uniqueKeysWithValues: (generatedTest?.orderedQuestions ?? []).map { ($0.id.uuidString, $0) })
                let hardMCQ = responses.first { tuple in
                    guard tuple.isCorrect, let q = qMap[tuple.questionId] else { return false }
                    return q.type == .mcq && q.difficulty == .hard
                }
                let mediumMCQ = responses.first { tuple in
                    guard tuple.isCorrect, let q = qMap[tuple.questionId] else { return false }
                    return q.type == .mcq && q.difficulty == .medium
                }
                let anyOEQ = responses.first { tuple in
                    guard tuple.isCorrect, let q = qMap[tuple.questionId] else { return false }
                    return q.type == .openEnded
                }
                let pick = hardMCQ ?? mediumMCQ ?? anyOEQ
                if let pick = pick, let q = qMap[pick.questionId] {
                    if coverage.spacedFollowUpBloom == nil { coverage.spacedFollowUpBloom = q.bloomCategory.rawValue }
                    if coverage.spacedFollowUpDifficultyRaw == nil {
                        let diff: QuestionDifficulty = (q.type == .openEnded) ? .hard : q.difficulty
                        coverage.spacedFollowUpDifficultyRaw = diff.rawValue
                    }
                }

                // If 8 categories are covered and spacedfollowup not set/passed, schedule it baseDelayDays out
                let hasEight = Set(coverage.coveredCategories).count >= 8
                if hasEight && coverage.spacedFollowUpPassedAt == nil && coverage.spacedFollowUpDueDate == nil && coverage.spacedFollowUpBloom != nil {
                    coverage.spacedFollowUpDueDate = Calendar.current.date(byAdding: .day, value: SpacedFollowUpConfig.baseDelayDays, to: Date())
                }
                try? modelContext.save()
            }
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

        // Trigger prefetch for the next lesson immediately after finishing
        let nextLessonNumber = lesson.lessonNumber + 1
        Task {
            let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
            prefetcher.prefetchLesson(book: book, lessonNumber: nextLessonNumber)
            print("DEBUG: Prefetch for Lesson \(nextLessonNumber) triggered from handleTestCompletion")
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
            let currentLesson = lesson
            print("DEBUG: Refreshing practice test for lesson \(currentLesson.lessonNumber)")
            
            // Get the primary idea for this lesson
            guard let primaryIdea = (book.ideas ?? []).first(where: { $0.id == currentLesson.primaryIdeaId }) else {
                throw NSError(domain: "LessonGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find idea for lesson \(currentLesson.lessonNumber)"])
            }
            // Invalidate existing session if present
            if let existingSession = try await fetchSessionAnyStatus(for: primaryIdea.id, type: "lesson_practice") {
                await MainActor.run {
                    self.modelContext.delete(existingSession)
                    try? self.modelContext.save()
                    self.activePracticeSession = nil
                    self.activeAttempt = nil
                    self.showingTest = false
                }
            }

            print("DEBUG: Refreshing test for idea: \(primaryIdea.title)")
            
            // Use refreshTest to force regeneration
            test = try await testGenerationService.refreshTest(
                for: primaryIdea,
                testType: "initial"
            )
            
            print("DEBUG: Refreshed test with \((test.questions ?? []).count) new questions")
            
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
                    s.ideaId == ideaId && s.type == type
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let sessions = try self.modelContext.fetch(descriptor)
            return sessions.first(where: { $0.status == PracticeSessionStatus.ready })
        }
    }

    private func fetchSessionAnyStatus(for ideaId: String, type: String) async throws -> PracticeSession? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PracticeSession>(
                predicate: #Predicate { s in
                    s.ideaId == ideaId && s.type == type
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

private enum TooltipLayout {
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let mixSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 8
    static let buttonSpacing: CGFloat = 12
    static let primaryButtonHeight: CGFloat = 56
    static let kebabButtonSize: CGFloat = 64
    static let cornerRadius: CGFloat = 36
}
