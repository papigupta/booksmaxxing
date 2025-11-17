import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Question Feedback Model

struct QuestionFeedback {
    let isCorrect: Bool
    let correctAnswer: String?
    // For OEQ, this is the 280-char author feedback line.
    let explanation: String
    // One-line Why (<=140 chars), for all types
    let why: String?
    let pointsEarned: Int
    let maxPoints: Int
    // Flag to drive OEQ-specific UI (exemplar section)
    let isOpenEnded: Bool
    // Whether the Why explanation is still loading asynchronously
    let isWhyPending: Bool
}

struct TestView: View {
    let idea: Idea
    let test: Test
    let openAIService: OpenAIService
    let onCompletion: (TestAttempt, Bool) -> Void
    var onSubmitted: ((TestAttempt) -> Void)? = nil
    var onExit: (() -> Void)? = nil
    var existingAttempt: TestAttempt? = nil  // Allow resuming from existing attempt
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var currentQuestionIndex = 0
    @State private var responses: [UUID: String] = [:]
    @State private var selectedOptions: [UUID: Set<Int>] = [:]
    @State private var currentAttempt: TestAttempt?
    @State private var isSubmitting = false
    @State private var evaluationResult: TestEvaluationResult?
    @State private var showingPrimer = false
    @State private var didMarkStreakToday: Bool = false
    
    // Immediate feedback states
    @State private var showingFeedback = false
    @State private var currentFeedback: QuestionFeedback?
    @State private var isEvaluatingQuestion = false
    @State private var questionEvaluations: [UUID: QuestionEvaluation] = [:]

    // BCal tracking state
    @State private var trackingStart: Date? = nil
    @State private var accumulatedSeconds: [UUID: TimeInterval] = [:]
    @State private var primerUsedMap: [UUID: Bool] = [:]
    @State private var optionChangesMap: [UUID: Int] = [:]
    @State private var lastSelectedIndex: [UUID: Int?] = [:]
    @State private var checkedQuestions: Set<UUID> = []
    
    // Attention tracking ("distractions")
    @State private var internalDistractions: Int = 0
    @State private var externalDistractions: Int = 0
    @State private var lastActivityAt: Date = Date()
    @State private var internalIdleActive: Bool = false
    @State private var lastInactiveAt: Date? = nil
    @State private var lifecycleObservers: [Any] = []
    private let attentionConfig = AttentionConfig()
    private let activityTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let awayStorageKey = "Attention.lastAwayAt"
    private var currentQuestion: Question? {
        test.orderedQuestions.indices.contains(currentQuestionIndex) ? test.orderedQuestions[currentQuestionIndex] : nil
    }
    
    private var progress: Double {
        let count = (test.questions ?? []).count
        guard count > 0 else { return 0.0 }
        return Double(currentQuestionIndex) / Double(count)
    }
    
    private var shouldShowResults: Bool {
        evaluationResult != nil && currentAttempt != nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress Bar
                ProgressBar(progress: progress, currentQuestion: currentQuestionIndex + 1, totalQuestions: (test.questions ?? []).count)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                
                DSDivider()
                
                // Question Content
                ZStack {
                    ScrollView {
                        if let question = currentQuestion {
                            QuestionView(
                                question: question,
                                questionNumber: currentQuestionIndex + 1,
                                response: binding(for: question),
                                selectedOptions: bindingForOptions(question),
                                isDisabled: showingFeedback,
                                onActivity: { markActivity() }
                            )
                            .padding(DS.Spacing.lg)
                        }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in
                        markActivity()
                    })
                }
                
                DSDivider()
                
                // Navigation Controls
                HStack(spacing: DS.Spacing.md) {
                    if currentQuestionIndex > 0 {
                        Button(action: previousQuestion) {
                            HStack(spacing: DS.Spacing.xs) {
                                DSIcon("chevron.left", size: 16)
                                Text("Previous")
                            }
                            .font(DS.Typography.captionBold)
                        }
                        .themeSecondaryButton()
                    }
                    
                    Spacer()
                    
                    if currentQuestionIndex < (test.questions ?? []).count - 1 {
                        if showingFeedback {
                            Button(action: nextQuestion) {
                                HStack(spacing: DS.Spacing.xs) {
                                    Text("Continue")
                                    DSIcon("chevron.right", size: 16)
                                }
                                .font(DS.Typography.captionBold)
                            }
                            .themePrimaryButton()
                        } else {
                            Button(action: checkAnswer) {
                                HStack(spacing: DS.Spacing.xs) {
                                    if isEvaluatingQuestion {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Check")
                                        DSIcon("checkmark", size: 16)
                                    }
                                }
                                .font(DS.Typography.captionBold)
                            }
                            .themePrimaryButton()
                            .disabled(!isCurrentQuestionAnswered() || isEvaluatingQuestion)
                        }
                    } else {
                        if showingFeedback {
                            Button(action: submitTest) {
                                Text("Finish Test")
                                    .font(DS.Typography.captionBold)
                            }
                            .themePrimaryButton()
                        } else {
                            Button(action: checkAnswer) {
                                HStack(spacing: DS.Spacing.xs) {
                                    if isEvaluatingQuestion {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Check")
                                        DSIcon("checkmark", size: 16)
                                    }
                                }
                                .font(DS.Typography.captionBold)
                            }
                            .themePrimaryButton()
                            .disabled(!isCurrentQuestionAnswered() || isEvaluatingQuestion)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            .background(themeManager.currentTokens(for: colorScheme).surface)
            .navigationTitle(idea.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Exit") {
                        // Save progress before exiting
                        if let attempt = currentAttempt, !attempt.isComplete {
                            saveCurrentResponse()
                            attempt.currentQuestionIndex = currentQuestionIndex
                            try? modelContext.save()
                        }
                        onExit?()
                        dismiss()
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingPrimer = true }) {
                        Text("Primer")
                            .font(DS.Typography.caption)
                            .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                    }
                }
            }
            .onAppear {
                initializeAttempt()
                streakManager.isTestingActive = true
                startTrackingForCurrentQuestion()
                lastActivityAt = Date()
                registerLifecycleObservers()
            }
            .onDisappear {
                streakManager.isTestingActive = false
                pauseTrackingForCurrentQuestion()
                unregisterLifecycleObservers()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive || phase == .background {
                    pauseTrackingForCurrentQuestion()
                    recordAwayStart(context: "ScenePhase Inactive/Background")
                } else if phase == .active {
                    handleReturnFromAway(context: "ScenePhase Active")
                }
            }
            .onChange(of: currentQuestionIndex) { _, _ in
                pauseTrackingForCurrentQuestion()
                startTrackingForCurrentQuestion()
                markActivity()
            }
            .onReceive(activityTicker) { _ in
                // Internal distraction detection: count once per idle episode
                let delta = Date().timeIntervalSince(lastActivityAt)
                if delta >= attentionConfig.inactivityThresholdSeconds {
                    if !internalIdleActive {
                        internalDistractions += 1
                        internalIdleActive = true
                    }
                }
            }
            .onChange(of: showingPrimer) { _, isPresented in
                if isPresented, let q = currentQuestion, !checkedQuestions.contains(q.id) {
                    primerUsedMap[q.id] = true
                    markActivity()
                }
            }
            .onChange(of: selectedOptions) { _, newVal in
                guard let q = currentQuestion, q.type == .mcq, !checkedQuestions.contains(q.id) else { return }
                let newIndex = newVal[q.id]?.first
                let prev = lastSelectedIndex[q.id] ?? nil
                if let p = prev, let n = newIndex, p != n {
                    optionChangesMap[q.id, default: 0] += 1
                }
                lastSelectedIndex[q.id] = newIndex
                markActivity()
            }
            .sheet(isPresented: Binding(
                get: { shouldShowResults },
                set: { if !$0 { evaluationResult = nil } }
            )) {
                if let result = evaluationResult, let attempt = currentAttempt {
                    TestResultsView(
                        idea: idea,
                        test: test,
                        attempt: attempt,
                        result: result,
                        onContinue: { attempt in
                            onCompletion(attempt, didMarkStreakToday)
                            dismiss()
                        }
                    )
                }
            }
            // Solid full-screen feedback presentation
            .fullScreenCover(isPresented: $showingFeedback) {
                if let feedback = currentFeedback {
                    FeedbackFullScreen(
                        feedback: feedback,
                        isLastQuestion: currentQuestionIndex >= (test.questions ?? []).count - 1,
                        onPrimaryAction: {
                            // Dismiss and continue/finish
                            showingFeedback = false
                            if currentQuestionIndex >= (test.questions ?? []).count - 1 {
                                submitTest()
                            } else {
                                nextQuestion()
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showingPrimer) {
                PrimerView(idea: idea, openAIService: openAIService)
                    .presentationDetents([.medium, .large])
            }
        }
        .background(themeManager.currentTokens(for: colorScheme).surface.ignoresSafeArea())
    }
    
    // MARK: - Helper Methods
    
    private func initializeAttempt() {
        if let existing = existingAttempt {
            // Resume from existing attempt
            currentAttempt = existing
            currentQuestionIndex = existing.currentQuestionIndex
            
            // Restore previous responses
            for response in (existing.responses ?? []) {
                switch response.questionType {
                case .mcq:
                    if let index = Int(response.userAnswer) {
                        selectedOptions[response.questionId] = [index]
                    }
                case .msq:
                    if let data = response.userAnswer.data(using: .utf8),
                       let indices = try? JSONDecoder().decode([Int].self, from: data) {
                        selectedOptions[response.questionId] = Set(indices)
                    }
                case .openEnded:
                    responses[response.questionId] = response.userAnswer
                }
                
                // Restore evaluations if available
                if response.isCorrect || response.pointsEarned > 0,
                   let evaluationData = response.evaluationData,
                   let evaluation = try? JSONDecoder().decode(QuestionEvaluation.self, from: evaluationData) {
                    questionEvaluations[response.questionId] = evaluation
                }
            }
        } else {
            // Ensure test is valid (regenerate if needed)
            let service = TestGenerationService(openAI: openAIService, modelContext: modelContext)
            Task {
                let validated: Test
                if service.isValid(test) == false {
                    validated = try await service.refreshTest(for: idea, testType: test.testType)
                } else {
                    validated = test
                }
                await MainActor.run {
                    // Create new attempt
                    let attempt = TestAttempt(testId: validated.id)
                    attempt.test = validated
                    if validated.attempts == nil { validated.attempts = [] }
                    validated.attempts?.append(attempt)
                    modelContext.insert(attempt)
                    currentAttempt = attempt
                }
            }
        }
    }
    
    private func binding(for question: Question) -> Binding<String> {
        Binding(
            get: { responses[question.id] ?? "" },
            set: { responses[question.id] = $0 }
        )
    }
    
    private func bindingForOptions(_ question: Question) -> Binding<Set<Int>> {
        Binding(
            get: { selectedOptions[question.id] ?? [] },
            set: { selectedOptions[question.id] = $0 }
        )
    }
    
    private func isCurrentQuestionAnswered() -> Bool {
        guard let question = currentQuestion else { return false }
        
        switch question.type {
        case .mcq, .msq:
            return !(selectedOptions[question.id] ?? []).isEmpty
        case .openEnded:
            return !(responses[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private func areAllQuestionsAnswered() -> Bool {
        for question in test.orderedQuestions {
            switch question.type {
            case .mcq, .msq:
                if (selectedOptions[question.id] ?? []).isEmpty {
                    return false
                }
            case .openEnded:
                if (responses[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            }
        }
        return true
    }
    
    private func checkAnswer() {
        guard let question = currentQuestion else { return }
        
        isEvaluatingQuestion = true
        finalizeTracking(for: question)
        saveCurrentResponse()
        markActivity()
        
        // Force save to ensure persistence
        try? modelContext.save()
        
        Task {
            do {
                // Evaluate the current question immediately
                let evaluation = try await evaluateCurrentQuestion(question)
                
                await MainActor.run {
                    let feedback = self.makeFeedback(from: evaluation, question: question)
                    self.questionEvaluations[question.id] = evaluation
                    self.currentFeedback = feedback
                    // Present full-screen feedback view
                    self.showingFeedback = true
                    self.isEvaluatingQuestion = false
                }

                await fetchWhyIfNeeded(for: question, baseEvaluation: evaluation)
            } catch {
                print("Error evaluating question: \(error)")
                await MainActor.run {
                    self.isEvaluatingQuestion = false
                }
            }
        }
    }
    
    private func nextQuestion() {
        pauseTrackingForCurrentQuestion()
        withAnimation {
            showingFeedback = false
            currentFeedback = nil
            currentQuestionIndex = min(currentQuestionIndex + 1, max((test.questions ?? []).count - 1, 0))
            // Save progress
            if let attempt = currentAttempt {
                attempt.currentQuestionIndex = currentQuestionIndex
                try? modelContext.save()
            }
        }
        startTrackingForCurrentQuestion()
        markActivity()
    }
    
    private func previousQuestion() {
        saveCurrentResponse()
        pauseTrackingForCurrentQuestion()
        withAnimation {
            currentQuestionIndex = max(currentQuestionIndex - 1, 0)
            // Save progress
            if let attempt = currentAttempt {
                attempt.currentQuestionIndex = currentQuestionIndex
                try? modelContext.save()
            }
        }
        startTrackingForCurrentQuestion()
        markActivity()
    }
    
    private func saveCurrentResponse() {
        guard let question = currentQuestion,
              let attempt = currentAttempt else { return }
        
        // Check if response already exists
        if let existingResponse = (attempt.responses ?? []).first(where: { $0.questionId == question.id }) {
            // Update existing response
            updateResponse(existingResponse, for: question)
        } else {
            // Create new response
            createResponse(for: question, attempt: attempt)
        }
        
        // Save to persistent storage
        try? modelContext.save()
    }
    
    private func updateResponse(_ response: QuestionResponse, for question: Question) {
        switch question.type {
        case .mcq, .msq:
            if let selected = selectedOptions[question.id], !selected.isEmpty {
                response.userAnswer = try! JSONEncoder().encode(Array(selected)).base64EncodedString()
            }
        case .openEnded:
            response.userAnswer = responses[question.id] ?? ""
        }

        // Ensure relationship to question is set for inverse linkage
        if response.question == nil { response.question = question }
        // Also ensure the question has this response in its collection (deduping by id)
        if question.responses == nil { question.responses = [] }
        if question.responses?.contains(where: { $0.id == response.id }) == false {
            question.responses?.append(response)
        }
    }
    
    private func createResponse(for question: Question, attempt: TestAttempt) {
        let userAnswer: String
        
        switch question.type {
        case .mcq:
            if let selected = selectedOptions[question.id]?.first {
                userAnswer = String(selected)
            } else {
                return
            }
        case .msq:
            if let selected = selectedOptions[question.id], !selected.isEmpty {
                let data = try! JSONEncoder().encode(Array(selected))
                userAnswer = String(data: data, encoding: .utf8)!
            } else {
                return
            }
        case .openEnded:
            userAnswer = responses[question.id] ?? ""
            if userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
        }
        
        let response = QuestionResponse(
            attemptId: attempt.id,
            questionId: question.id,
            questionType: question.type,
            userAnswer: userAnswer
        )
        // Link relationships so inverse queries work (IdeaResponsesView relies on this)
        response.question = question
        modelContext.insert(response)
        if attempt.responses == nil { attempt.responses = [] }
        attempt.responses?.append(response)
        if question.responses == nil { question.responses = [] }
        question.responses?.append(response)
        print("DEBUG: Created and saved response for question \(question.id), total responses now: \((attempt.responses ?? []).count)")
    }

    private func makeFeedback(from evaluation: QuestionEvaluation, question: Question) -> QuestionFeedback {
        let normalizedWhy = trimmed(evaluation.why)
        let isOpenEnded = question.type == .openEnded
        let pendingWhy = !isOpenEnded && normalizedWhy == nil

        return QuestionFeedback(
            isCorrect: evaluation.isCorrect,
            correctAnswer: evaluation.correctAnswer,
            explanation: evaluation.feedback,
            why: normalizedWhy,
            pointsEarned: evaluation.pointsEarned,
            maxPoints: question.difficulty.pointValue,
            isOpenEnded: isOpenEnded,
            isWhyPending: pendingWhy
        )
    }

    private func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func fetchWhyIfNeeded(for question: Question, baseEvaluation: QuestionEvaluation) async {
        let isOpenEnded = await MainActor.run { question.type == .openEnded }
        if isOpenEnded { return }
        if trimmed(baseEvaluation.why) != nil { return }

        let evaluationService = TestEvaluationService(openAI: openAIService, modelContext: modelContext)
        guard let rawWhy = await evaluationService.fetchWhy(for: question, idea: idea),
              let normalizedWhy = trimmed(rawWhy) else { return }

        let updatedEvaluation = QuestionEvaluation(
            questionId: baseEvaluation.questionId,
            isCorrect: baseEvaluation.isCorrect,
            pointsEarned: baseEvaluation.pointsEarned,
            feedback: baseEvaluation.feedback,
            correctAnswer: baseEvaluation.correctAnswer,
            why: normalizedWhy
        )

        await MainActor.run {
            self.questionEvaluations[question.id] = updatedEvaluation
            if self.showingFeedback, self.currentQuestion?.id == question.id {
                self.currentFeedback = self.makeFeedback(from: updatedEvaluation, question: question)
            }
        }
    }

    private func kickOffWhyPrefetchIfNeeded(for question: Question) {
        guard question.type != .openEnded else { return }
        let evaluationService = TestEvaluationService(openAI: openAIService, modelContext: modelContext)
        let ideaSnapshot = idea

        Task(priority: .background) {
            await evaluationService.prefetchWhyIfNeeded(for: question, idea: ideaSnapshot)
        }
    }
    
    private func evaluateCurrentQuestion(_ question: Question) async throws -> QuestionEvaluation {
        // Create a temporary response for evaluation
        let userAnswer: String
        
        switch question.type {
        case .mcq:
            if let selected = selectedOptions[question.id]?.first {
                userAnswer = String(selected)
            } else {
                userAnswer = "-1" // Invalid answer
            }
        case .msq:
            if let selected = selectedOptions[question.id], !selected.isEmpty {
                let data = try! JSONEncoder().encode(Array(selected))
                userAnswer = String(data: data, encoding: .utf8)!
            } else {
                userAnswer = "[]" // Empty array
            }
        case .openEnded:
            userAnswer = responses[question.id] ?? ""
        }
        
        let tempResponse = QuestionResponse(
            attemptId: currentAttempt?.id ?? UUID(),
            questionId: question.id,
            questionType: question.type,
            userAnswer: userAnswer
        )
        
        let evaluationService = TestEvaluationService(openAI: openAIService, modelContext: modelContext)
        return try await evaluationService.evaluateQuestion(response: tempResponse, question: question, idea: idea)
    }
    
    private func submitTest() {
        guard let attempt = currentAttempt else { return }
        
        // Save the current response before submitting
        saveCurrentResponse()
        if let q = currentQuestion { finalizeTracking(for: q) }
        
        // Also ensure all responses are saved for all questions
        for question in test.orderedQuestions {
            // Check if response already exists
            if (attempt.responses ?? []).first(where: { $0.questionId == question.id }) == nil {
                // Create response if it doesn't exist but we have an answer
                switch question.type {
                case .mcq, .msq:
                    if let selected = selectedOptions[question.id], !selected.isEmpty {
                        createResponse(for: question, attempt: attempt)
                    }
                case .openEnded:
                    if let answer = responses[question.id], !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        createResponse(for: question, attempt: attempt)
                    }
                }
            }
        }
        
        // Save all responses to persistent storage
        try? modelContext.save()
        
        print("DEBUG: About to submit test - attempt has \((attempt.responses ?? []).count) responses")
        for (index, response) in (attempt.responses ?? []).enumerated() {
            print("DEBUG: Response \(index): questionId=\(response.questionId)")
        }
        
        isSubmitting = true
        
        Task {
            do {
                // Use pre-computed evaluations to create final result
                var totalScore = 0
                var correctCount = 0
                var evaluationDetails: [QuestionEvaluation] = []
                
                // Update attempt with all evaluations
                for question in test.orderedQuestions {
                    if let evaluation = questionEvaluations[question.id] {
                        evaluationDetails.append(evaluation)
                        if evaluation.isCorrect {
                            correctCount += 1
                            totalScore += evaluation.pointsEarned
                        }
                        
                        // Update the actual response in the attempt
                        if let response = (attempt.responses ?? []).first(where: { $0.questionId == question.id }) {
                            response.isCorrect = evaluation.isCorrect
                            response.pointsEarned = evaluation.pointsEarned
                            response.evaluationData = try? JSONEncoder().encode(evaluation)
                        }
                    }
                }
                
                // Update attempt
                attempt.score = totalScore
                attempt.completedAt = Date()
                attempt.isComplete = true
                // Compute and persist Brain Calories for this session
                let bcal = computeLessonBCal()
                attempt.brainCalories = bcal
                // Persist Accuracy snapshot
                attempt.accuracyTotal = (attempt.responses ?? []).count
                attempt.accuracyCorrect = (attempt.responses ?? []).filter { $0.isCorrect }.count
                // Persist Distractions (store in existing attentionPauses field)
                attempt.attentionPauses = internalDistractions + externalDistractions
                
                // Determine mastery
                let allCorrect = correctCount == (test.questions ?? []).count
                if allCorrect {
                    if test.testType == "review" {
                        attempt.masteryAchieved = .solid
                    } else {
                        // Drop 'fragile' mastery; do not set mastery on initial
                        attempt.masteryAchieved = .none
                    }
                }
                
                // Save changes
                try modelContext.save()
                
                // Compute dynamic max score based on the questions in this test
                let dynamicMaxScore = (test.questions ?? []).reduce(0) { acc, q in
                    acc + q.difficulty.pointValue
                }

                let result = TestEvaluationResult(
                    totalScore: totalScore,
                    maxScore: dynamicMaxScore,
                    correctCount: correctCount,
                    totalQuestions: (test.questions ?? []).count,
                    masteryAchieved: attempt.masteryAchieved,
                    evaluationDetails: evaluationDetails
                )
                
                await MainActor.run {
                    evaluationResult = result
                    isSubmitting = false
                    // Mark daily streak on successful test completion (idempotent per day)
                    didMarkStreakToday = streakManager.markActivity()
                }

                // Notify host that the test has been submitted (prefetch next lesson, etc.)
                await MainActor.run { onSubmitted?(attempt) }
            } catch {
                print("Error submitting test: \(error)")
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - BCal Tracking Helpers

extension TestView {
    private func startTrackingForCurrentQuestion() {
        guard let q = currentQuestion else { return }
        if checkedQuestions.contains(q.id) { trackingStart = nil; return }
        trackingStart = Date()
        kickOffWhyPrefetchIfNeeded(for: q)
    }

    private func pauseTrackingForCurrentQuestion() {
        guard let q = currentQuestion, let start = trackingStart else { return }
        let delta = Date().timeIntervalSince(start)
        accumulatedSeconds[q.id, default: 0] += max(0, delta)
        trackingStart = nil
    }

    private func finalizeTracking(for question: Question) {
        if currentQuestion?.id == question.id { pauseTrackingForCurrentQuestion() }
        checkedQuestions.insert(question.id)
    }

    private func computeLessonBCal() -> Int {
        var items: [(BCalQuestionContext, BCalQuestionSignals)] = []
        for q in test.orderedQuestions {
            let secs = accumulatedSeconds[q.id] ?? defaultLatency(for: q)
            let usedPrimer = primerUsedMap[q.id] ?? false
            let changes = optionChangesMap[q.id] ?? 0
            let ctx = BCalQuestionContext(
                type: q.type,
                difficulty: q.difficulty,
                isCurveball: q.isCurveball,
                isSpacedFollowUp: q.isSpacedFollowUp,
                isReview: false
            )
            let sig = BCalQuestionSignals(latencySeconds: secs, primerUsed: usedPrimer, optionChanges: changes)
            items.append((ctx, sig))
        }
        return BCalEngine.shared.bcalForLesson(items: items)
    }

    private func defaultLatency(for q: Question) -> Double {
        switch q.type {
        case .mcq, .msq: return 15.0
        case .openEnded: return 25.0
        }
    }

    private func markActivity() {
        lastActivityAt = Date()
        if internalIdleActive { internalIdleActive = false }
    }

    // MARK: - App Lifecycle Observers (extra safety for external distractions)
    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        #if os(iOS)
        let willResign = center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            self.pauseTrackingForCurrentQuestion()
            self.recordAwayStart(context: "iOS willResignActive")
        }
        let didEnterBg = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            self.pauseTrackingForCurrentQuestion()
            self.recordAwayStart(context: "iOS didEnterBackground")
        }
        let willEnterFg = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            self.handleReturnFromAway(context: "iOS willEnterForeground")
        }
        let didBecomeActive = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            self.handleReturnFromAway(context: "iOS didBecomeActive")
        }
        lifecycleObservers = [willResign, didEnterBg, willEnterFg, didBecomeActive]
        #elseif os(macOS)
        let willResign = center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            self.pauseTrackingForCurrentQuestion()
            if self.lastInactiveAt == nil { self.lastInactiveAt = Date() }
            print("[Attention] macOS willResignActive at \(String(describing: self.lastInactiveAt))")
        }
        let didHide = center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            self.pauseTrackingForCurrentQuestion()
            if self.lastInactiveAt == nil { self.lastInactiveAt = Date() }
            print("[Attention] macOS didHide at \(String(describing: self.lastInactiveAt))")
        }
        let didBecomeActive = center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            self.handleReturnFromAway(context: "macOS didBecomeActive")
        }
        lifecycleObservers = [willResign, didHide, didBecomeActive]
        #endif
    }

    private func unregisterLifecycleObservers() {
        let center = NotificationCenter.default
        for token in lifecycleObservers { center.removeObserver(token) }
        lifecycleObservers.removeAll()
    }

    private func handleReturnFromAway(context: String) {
        self.startTrackingForCurrentQuestion()

        var counted = false
        if let away = self.lastInactiveAt {
            let delta = Date().timeIntervalSince(away)
            print("[Attention] \(context); away(memory)=\(delta)s (threshold=\(self.attentionConfig.awayThresholdSeconds))")
            if delta > self.attentionConfig.awayThresholdSeconds {
                self.externalDistractions += 1
                counted = true
                print("[Attention] External distraction counted from memory (+1). Total=\(self.externalDistractions)")
            }
            self.lastInactiveAt = nil
        }

        let ts = UserDefaults.standard.double(forKey: awayStorageKey)
        if ts > 0 {
            let started = Date(timeIntervalSince1970: ts)
            let delta = Date().timeIntervalSince(started)
            print("[Attention] \(context); away(persisted)=\(delta)s (threshold=\(self.attentionConfig.awayThresholdSeconds))")
            if delta > self.attentionConfig.awayThresholdSeconds {
                if !counted {
                    self.externalDistractions += 1
                    print("[Attention] External distraction counted from persisted (+1). Total=\(self.externalDistractions)")
                } else {
                    print("[Attention] Already counted from memory; skipping persisted")
                }
            }
            UserDefaults.standard.removeObject(forKey: awayStorageKey)
        }

        self.markActivity()
    }

    private func recordAwayStart(context: String) {
        if self.lastInactiveAt == nil { self.lastInactiveAt = Date() }
        if UserDefaults.standard.object(forKey: awayStorageKey) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: awayStorageKey)
        }
        print("[Attention] Record away start (\(context)) at \(String(describing: self.lastInactiveAt))")
    }
}

// MARK: - Question View Component

struct QuestionView: View {
    let question: Question
    let questionNumber: Int
    @Binding var response: String
    @Binding var selectedOptions: Set<Int>
    let isDisabled: Bool
    let onActivity: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // Question Header
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Question \(questionNumber)")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(DS.Colors.secondaryText)
                    
                    HStack(spacing: DS.Spacing.xs) {
                        DifficultyBadge(difficulty: question.difficulty)
                        // For curveball or spacedfollowup questions, show 'Retrieval' and a badge
                        if question.isCurveball {
                            RetrievalBadge()
                            CurveballBadge()
                        } else if question.isSpacedFollowUp {
                            RetrievalBadge()
                            SpacedFollowUpBadge()
                        } else {
                            BloomBadge(category: question.bloomCategory)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Question Text
            Text(question.questionText)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            // Answer Input
            switch question.type {
            case .mcq:
                MCQOptions(options: question.options ?? [], selectedOptions: $selectedOptions, isDisabled: isDisabled)
            case .msq:
                MSQOptions(options: question.options ?? [], selectedOptions: $selectedOptions, isDisabled: isDisabled)
            case .openEnded:
                OpenEndedInput(response: $response, isDisabled: isDisabled, onActivity: onActivity)
            }
        }
    }
}

// MARK: - Option Components

struct MCQOptions: View {
    let options: [String]
    @Binding var selectedOptions: Set<Int>
    let isDisabled: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(action: {
                    if !isDisabled {
                        selectedOptions = [index]
                    }
                }) {
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: selectedOptions.contains(index) ? "circle.inset.filled" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedOptions.contains(index) ? theme.primary : theme.onSurface.opacity(0.4))
                        
                        Text(option)
                            .font(DS.Typography.body)
                            .foregroundStyle(theme.onSurface)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(
                        Rectangle()
                            .fill(selectedOptions.contains(index) ? theme.primaryContainer.opacity(0.35) : theme.surfaceVariant)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedOptions.contains(index) ? theme.primary : theme.outline, lineWidth: DS.BorderWidth.thin)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct MSQOptions: View {
    let options: [String]
    @Binding var selectedOptions: Set<Int>
    let isDisabled: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Select all that apply")
                .font(DS.Typography.caption)
                .foregroundStyle(theme.onSurface.opacity(0.7))
                .italic()
            
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(action: {
                    if !isDisabled {
                        if selectedOptions.contains(index) {
                            selectedOptions.remove(index)
                        } else {
                            selectedOptions.insert(index)
                        }
                    }
                }) {
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: selectedOptions.contains(index) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedOptions.contains(index) ? theme.primary : theme.onSurface.opacity(0.4))
                        
                        Text(option)
                            .font(DS.Typography.body)
                            .foregroundStyle(theme.onSurface)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(
                        Rectangle()
                            .fill(selectedOptions.contains(index) ? theme.primaryContainer.opacity(0.35) : theme.surfaceVariant)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedOptions.contains(index) ? theme.primary : theme.outline, lineWidth: DS.BorderWidth.thin)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct OpenEndedInput: View {
    @Binding var response: String
    let isDisabled: Bool
    var onActivity: (() -> Void)? = nil
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Your response (2-4 sentences)")
                .font(DS.Typography.caption)
                .foregroundStyle(theme.onSurface.opacity(0.7))
            
            TextEditor(text: $response)
                .font(DS.Typography.body)
                .foregroundStyle(theme.onSurface)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .frame(minHeight: 120)
                .padding(DS.Spacing.md)
                .background(
                    Rectangle()
                        .fill(theme.surfaceVariant)
                        .overlay(
                            Rectangle()
                                .stroke(theme.outline, lineWidth: DS.BorderWidth.thin)
                        )
                )
                .disabled(isDisabled)
                .onChange(of: response) { _, _ in
                    onActivity?()
                }
        }
    }
}

// MARK: - Feedback Full Screen (Solid)

struct FeedbackFullScreen: View {
    let feedback: QuestionFeedback
    let isLastQuestion: Bool
    let onPrimaryAction: () -> Void
    @State private var showExemplar: Bool = false
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    private var statusLabel: (text: String, color: Color) {
        let ratio = feedback.maxPoints > 0 ? Double(feedback.pointsEarned) / Double(feedback.maxPoints) : 0
        switch ratio {
        case let r where r >= 0.70: return ("On Track", .green)
        case let r where r >= 0.50: return ("Close", .orange)
        default: return ("Off Track", .red)
        }
    }

    private var feedbackSegments: [(label: String, body: String)] {
        func normalize(_ s: String) -> String {
            var t = s
            // Normalize common model prefixes and inject separators for parsing
            let pairs: [(String, String)] = [
                ("BL/Polish:", " | Polish:"),
                ("BL/Do:", " | Do:"),
                ("BL/Keep:", " | Keep:"),
                ("BL/KEEP:", " | Keep:"),
                ("BL/DO:", " | Do:"),
                ("BL/POLISH:", " | Polish:"),
                ("BottomLine:", "Summary:"),
                ("BL:", "Summary:")
            ]
            for (k, v) in pairs { t = t.replacingOccurrences(of: k, with: v) }
            return t
        }
        let normalized = normalize(feedback.explanation)
        return normalized
            .components(separatedBy: " | ")
            .compactMap { segment in
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if let idx = trimmed.firstIndex(of: ":") {
                    let label = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
                    let body = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                    return (label.uppercased(), body)
                } else {
                    return ("SUMMARY", trimmed)
                }
            }
    }

    private func friendlyLabel(_ raw: String) -> String {
        let tokens = raw.uppercased().replacingOccurrences(of: " ", with: "").split(separator: "/")
        if tokens.contains("BL") || tokens.contains("BOTTOMLINE") { return "Summary" }
        if tokens.contains("KEEP") { return "What worked" }
        if tokens.contains("FIX") { return "What to fix" }
        if tokens.contains("POLISH") { return "Polish" }
        if tokens.contains("DO") { return "Next step" }
        return raw.capitalized
    }

    private var displayRows: [(title: String, body: String)] {
        // Map segments into a simple 3-line structure: Summary, What to fix/What worked, Next step
        var dict: [String: String] = [:]
        for seg in feedbackSegments {
            let label = friendlyLabel(seg.label)
            dict[label] = seg.body
        }
        var rows: [(String, String)] = []
        if let s = dict["Summary"] { rows.append(("Summary", s)) }
        if let fix = dict["What to fix"] ?? dict["Polish"] ?? dict["What worked"] {
            let title = dict["What to fix"] != nil ? "What to fix" : (dict["Polish"] != nil ? "Polish" : "What worked")
            rows.append((title, fix))
        }
        if let d = dict["Next step"] { rows.append(("Next step", d)) }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    // Header
                    HStack(spacing: DS.Spacing.md) {
                        // Show explicit correctness with check/x icon for all question types
                        DSIcon(feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill", size: 36)
                            .foregroundStyle(feedback.isCorrect ? .green : .red)
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(feedback.isCorrect ? "Correct" : "Incorrect")
                                .font(DS.Typography.headline)
                                .foregroundStyle(DS.Colors.primaryText)
                        }
                        Spacer()
                        Text(statusLabel.text)
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(statusLabel.color)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .overlay(
                                Capsule().stroke(statusLabel.color, lineWidth: DS.BorderWidth.thin)
                            )
                    }
                    
                    // Author Feedback (micro, ≤280 chars for OEQ)
                    if !feedback.explanation.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            Text("Author Feedback")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(DS.Colors.primaryText)
                            ForEach(Array(displayRows.enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                    Text(row.title)
                                        .font(DS.Typography.captionBold)
                                        .foregroundStyle(DS.Colors.primaryText)
                                    Text(row.body)
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // Why? (<=140 chars), always eligible for both MCQ/OEQ if present
                    if let why = feedback.why, !why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Why?")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(DS.Colors.primaryText)
                            Text(String(why.prefix(140)))
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if !feedback.isOpenEnded && feedback.isWhyPending {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Why?")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(DS.Colors.primaryText)
                            HStack(spacing: DS.Spacing.xs) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Fetching explanation…")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.secondaryText)
                            }
                        }
                    }
                    
                    // Exemplar for OEQ (collapsed), or Correct Answer for objective items
                    if feedback.isOpenEnded, let exemplar = feedback.correctAnswer, !exemplar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            HStack {
                                Text("Author’s Exemplar")
                                    .font(DS.Typography.captionBold)
                                    .foregroundStyle(DS.Colors.primaryText)
                                Spacer()
                                Button(action: { withAnimation { showExemplar.toggle() } }) {
                                    HStack(spacing: 4) {
                                        Text(showExemplar ? "Hide" : "Show")
                                        Image(systemName: showExemplar ? "chevron.up" : "chevron.down")
                                    }
                                    .font(DS.Typography.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            if showExemplar {
                                Text(exemplar)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else if !feedback.isOpenEnded, !feedback.isCorrect, let correct = feedback.correctAnswer {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text("Correct Answer")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(DS.Colors.primaryText)
                            Text(correct)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(DS.Spacing.lg)
            }
            
            DSDivider()
            
            // Primary action
            HStack {
                Button(action: onPrimaryAction) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(isLastQuestion ? "Finish Test" : "Continue")
                        if !isLastQuestion { DSIcon("chevron.right", size: 16) }
                    }
                    .font(DS.Typography.captionBold)
                }
                .themePrimaryButton()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
        .background(themeManager.currentTokens(for: colorScheme).background.ignoresSafeArea())
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double
    let currentQuestion: Int
    let totalQuestions: Int
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        let clampedProgress: Double = {
            guard progress.isFinite else { return 0 }
            return min(max(progress, 0), 1)
        }()

        VStack(spacing: DS.Spacing.xs) {
            HStack {
                let safeTotal = max(totalQuestions, 1)
                let safeCurrent = min(max(currentQuestion, 1), safeTotal)
                Text("Question \(safeCurrent) of \(safeTotal)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(theme.onSurface.opacity(0.7))
                
                Spacer()
                
                Text("\(Int(clampedProgress * 100))%")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(theme.onSurface)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(theme.surfaceVariant)
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(theme.primary)
                        .frame(width: max(0, geometry.size.width * clampedProgress), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Badges

struct DifficultyBadge: View {
    let difficulty: QuestionDifficulty
    
    var body: some View {
        Text(difficulty.rawValue)
            .font(DS.Typography.caption)
            .foregroundStyle(colorForDifficulty)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .stroke(colorForDifficulty, lineWidth: DS.BorderWidth.thin)
            )
    }
    
    private var colorForDifficulty: Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

struct BloomBadge: View {
    let category: BloomCategory
    
    var body: some View {
        Text(category.rawValue)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Colors.secondaryText)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
            )
    }
}

struct RetrievalBadge: View {
    var body: some View {
        Text("Retrieval")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Colors.secondaryText)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
            )
            .accessibilityLabel("Retrieval")
    }
}

struct CurveballBadge: View {
    var body: some View {
        Text("CB")
            .font(DS.Typography.captionBold)
            .foregroundStyle(Color.black)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.9))
            .cornerRadius(3)
            .overlay(
                Rectangle()
                    .stroke(Color.yellow, lineWidth: DS.BorderWidth.thin)
            )
            .accessibilityLabel("Curveball")
    }
}

struct SpacedFollowUpBadge: View {
    var body: some View {
        Text("SPFU")
            .font(DS.Typography.captionBold)
            .foregroundStyle(Color.black)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.9))
            .cornerRadius(3)
            .overlay(
                Rectangle()
                    .stroke(Color.blue, lineWidth: DS.BorderWidth.thin)
            )
            .accessibilityLabel("Spaced Follow-up")
    }
}
