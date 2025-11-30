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
    let correctAnswerDetail: String?
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
    @AppStorage(DevPreferenceKeys.showPreviousQuestionButton) private var showPreviousQuestionButton: Bool = false
    
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
        let theme = themeManager.currentTokens(for: colorScheme)
        return NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    Button(action: handleExitTapped) {
                        DSIcon("multiply", size: 14)
                    }
                    .dsPaletteSecondaryIconButton(diameter: 38)
                    .accessibilityLabel("Exit test")

                    Spacer()

                    Button(action: { showingPrimer = true }) {
                        Text("Primer")
                    }
                    .dsPaletteSecondaryButton()
                }
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.lg)

                // Progress Bar
                ProgressBar(progress: progress)
                    .padding(.horizontal, DS.Spacing.xxl)
                    .padding(.bottom, DS.Spacing.md)

                DSDivider()
                
                if let question = currentQuestion {
                    QuestionMetadataRow(question: question)
                        .padding(.horizontal, DS.Spacing.xxl)
                        .padding(.top, DS.Spacing.xl)
                        .padding(.bottom, DS.Spacing.xl)
                }
                
                // Question Content
                ZStack {
                    ScrollView {
                        if let question = currentQuestion {
                            QuestionView(
                                question: question,
                                response: binding(for: question),
                                selectedOptions: bindingForOptions(question),
                                isDisabled: showingFeedback,
                                onActivity: { markActivity() }
                            )
                            .padding(.bottom, DS.Spacing.lg)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xxl)
                    .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in
                        markActivity()
                    })
                }
                
                DSDivider()
                
                // Navigation Controls
                HStack(spacing: DS.Spacing.md) {
                    if showPreviousQuestionButton && currentQuestionIndex > 0 {
                        Button(action: previousQuestion) {
                            HStack(spacing: DS.Spacing.xs) {
                                DSIcon("chevron.left", size: 16)
                                Text("Previous")
                            }
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(theme.onSurface)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    if currentQuestionIndex < (test.questions ?? []).count - 1 {
                        if showingFeedback {
                            Button(action: nextQuestion) {
                                TestPrimaryButtonLabel(text: "Continue", isLoading: false)
                            }
                            .dsPalettePrimaryButton()
                        } else {
                            Button(action: checkAnswer) {
                                TestPrimaryButtonLabel(text: "Check", isLoading: isEvaluatingQuestion)
                            }
                            .dsPalettePrimaryButton()
                            .disabled(!isCurrentQuestionAnswered() || isEvaluatingQuestion)
                        }
                    } else {
                        if showingFeedback {
                            Button(action: submitTest) {
                                TestPrimaryButtonLabel(text: "Finish Test", isLoading: false)
                            }
                            .dsPalettePrimaryButton()
                        } else {
                            Button(action: checkAnswer) {
                                TestPrimaryButtonLabel(text: "Check", isLoading: isEvaluatingQuestion)
                            }
                            .dsPalettePrimaryButton()
                            .disabled(!isCurrentQuestionAnswered() || isEvaluatingQuestion)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.md)
            }
            .background(theme.surface)
            .navigationBarHidden(true)
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
            .fullScreenCover(isPresented: Binding(
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
        .background(theme.background.ignoresSafeArea())
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
    
    private func handleExitTapped() {
        if let attempt = currentAttempt, !attempt.isComplete {
            saveCurrentResponse()
            attempt.currentQuestionIndex = currentQuestionIndex
            try? modelContext.save()
        }
        onExit?()
        dismiss()
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
                    self.triggerAnswerHaptic(isCorrect: feedback.isCorrect)
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
            correctAnswerDetail: formattedCorrectAnswer(for: question, evaluation: evaluation),
            explanation: evaluation.feedback,
            why: normalizedWhy,
            pointsEarned: evaluation.pointsEarned,
            maxPoints: question.difficulty.pointValue,
            isOpenEnded: isOpenEnded,
            isWhyPending: pendingWhy
        )
    }

    private func formattedCorrectAnswer(for question: Question, evaluation: QuestionEvaluation) -> String? {
        guard question.type != .openEnded else { return nil }
        if let indices = question.correctAnswers, !indices.isEmpty {
            let options = question.options ?? []
            let formatted = indices.compactMap { idx -> String? in
                guard idx >= 0 else { return nil }
                let order = "\(idx + 1)."
                let text = idx < options.count ? options[idx] : ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return order
                }
                return "\(idx + 1). \(text)"
            }
            if formatted.isEmpty { return nil }
            if question.type == .mcq { return formatted.first }
            return formatted.joined(separator: "\n")
        }
        return evaluation.correctAnswer
    }

    private func triggerAnswerHaptic(isCorrect: Bool) {
        #if os(iOS)
        if isCorrect {
            AnswerHaptics.shared.playCorrect()
        } else {
            AnswerHaptics.shared.playIncorrect()
        }
        #endif
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
    @Binding var response: String
    @Binding var selectedOptions: Set<Int>
    let isDisabled: Bool
    let onActivity: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            // Question Text
            Text(question.questionText)
                .font(DS.Typography.fraunces(size: 18, weight: .semibold))
                .tracking(DS.Typography.tightTracking(for: 18))
                .foregroundStyle(DS.Colors.primaryText)
                .lineSpacing(5)
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
                let isSelected = selectedOptions.contains(index)
                let selectionAnimation = Animation.interpolatingSpring(mass: 0.8, stiffness: 150, damping: 18, initialVelocity: 0)
                Button(action: {
                    if !isDisabled {
                        withAnimation(selectionAnimation) {
                            selectedOptions = [index]
                        }
                    }
                }) {
                    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    ZStack(alignment: .leading) {
                        shape
                            .fill(isSelected ? theme.primaryContainer.opacity(0.5) : theme.surfaceVariant)
                            .overlay(
                                shape.strokeBorder(isSelected ? theme.primary : Color.clear, lineWidth: 1.5)
                            )
                            .animation(selectionAnimation, value: isSelected)

                        Text(option)
                            .font(DS.Typography.body)
                            .tracking(DS.Typography.tightTracking(for: 16))
                            .foregroundStyle(theme.onSurface)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, DS.Spacing.lg)
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(shape)
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
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedOptions.contains(index) ? theme.primaryContainer.opacity(0.35) : theme.surfaceVariant)
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
    @FocusState private var isFocused: Bool
    @State private var measuredHeight: CGFloat = 120
    private let minEditorHeight: CGFloat = 120
    private let maxEditorHeight: CGFloat = 260
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        let platformFont: PlatformFont = {
            #if os(iOS)
            return UIFont(name: "Fraunces", size: 16) ?? UIFont.preferredFont(forTextStyle: .body)
            #else
            return NSFont(name: "Fraunces", size: 16) ?? NSFont.preferredFont(forTextStyle: .body)
            #endif
        }()
        let platformColor: PlatformColor = {
            #if os(iOS)
            return UIColor(theme.onSurface)
            #else
            return NSColor(theme.onSurface)
            #endif
        }()
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            AutoGrowingTextView(
                text: $response,
                measuredHeight: $measuredHeight,
                minHeight: minEditorHeight,
                maxHeight: maxEditorHeight,
                isDisabled: isDisabled,
                font: platformFont,
                textColor: platformColor,
                kerning: DS.Typography.tightTracking(for: 16),
                onActivity: onActivity
            )
            .focused($isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.surfaceVariant)
            )
            .onAppear(perform: focusIfNeeded)
            .onChange(of: isDisabled) { _, newValue in
                if newValue {
                    isFocused = false
                } else {
                    focusIfNeeded()
                }
            }
        }
    }

    private func focusIfNeeded() {
        guard !isDisabled else { return }
        DispatchQueue.main.async {
            isFocused = true
        }
    }
}

// MARK: - Feedback Full Screen (Solid)

struct FeedbackFullScreen: View {
    let feedback: QuestionFeedback
    let isLastQuestion: Bool
    let onPrimaryAction: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    private enum HeroState {
        case mcqCorrect, mcqIncorrect, oeqBad, oeqOkay, oeqGood, oeqGreat
    }

    private let heroIconSize: CGFloat = 64
    private let haloSize: CGFloat = 128
    private let haloBlur: CGFloat = 100
    private let feedbackLineSpacing: CGFloat = 4
    private let feedbackTracking: CGFloat = -0.48

    private var scoreRatio: Double {
        guard feedback.maxPoints > 0 else { return 0 }
        return min(max(Double(feedback.pointsEarned) / Double(feedback.maxPoints), 0), 1)
    }

    private var heroState: HeroState {
        if !feedback.isOpenEnded {
            return feedback.isCorrect ? .mcqCorrect : .mcqIncorrect
        }
        switch scoreRatio {
        case ..<0.40: return .oeqBad
        case ..<0.70: return .oeqOkay
        case ..<0.90: return .oeqGood
        default: return .oeqGreat
        }
    }

    private var heroCopy: String {
        switch heroState {
        case .mcqCorrect: return "Clean hit. This one’s locked."
        case .mcqIncorrect: return "Missed it. Let’s shore this idea up."
        case .oeqBad: return "Start over—the core idea’s missing."
        case .oeqOkay: return "Pieces are there, but the logic’s fuzzy."
        case .oeqGood: return "Solid push—tighten the details."
        case .oeqGreat: return "Crushed it—clear, vivid reasoning."
        }
    }

    private var heroIsPositive: Bool {
        switch heroState {
        case .mcqCorrect, .oeqGood, .oeqGreat:
            return true
        default:
            return false
        }
    }

    private var iconName: String {
        heroIsPositive ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var accentColor: Color {
        let theme = themeManager.currentTokens(for: colorScheme)
        return heroIsPositive ? theme.success : theme.error
    }

    private var pointsLine: String {
        return "\(feedback.pointsEarned)/\(feedback.maxPoints) pts"
    }

    private var trimmedWhy: String? {
        trimmed(feedback.why)
    }

    private var exemplarText: String? {
        guard feedback.isOpenEnded else { return nil }
        return trimmed(feedback.correctAnswer)
    }

    private var shouldShowSummary: Bool {
        feedback.isOpenEnded && heroIsPositive && !displayRows.isEmpty
    }

    private var feedbackSegments: [(label: String, body: String)] {
        func normalize(_ s: String) -> String {
            var t = s
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
        let theme = themeManager.currentTokens(for: colorScheme)
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    heroSection(theme: theme)
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        summarySection(theme: theme)
                        correctAnswerSection(theme: theme)
                        whySection(theme: theme)
                        exemplarSection(theme: theme)
                    }
                }
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.lg)
            }

            DSDivider()

            HStack {
                Spacer()
                Button(action: onPrimaryAction) {
                    TestPrimaryButtonLabel(text: isLastQuestion ? "Finish Test" : "Continue", isLoading: false)
                }
                .dsPalettePrimaryButton()
            }
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.vertical, DS.Spacing.md)
        }
        .background(theme.background.ignoresSafeArea())
    }

    private func heroSection(theme: ThemeTokens) -> some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.7))
                    .frame(width: haloSize, height: haloSize)
                    .blur(radius: haloBlur)
                Image(systemName: iconName)
                    .font(.system(size: heroIconSize, weight: .bold))
                    .foregroundColor(accentColor)
            }
            .frame(width: haloSize, height: haloSize)
            .frame(maxWidth: .infinity)

            Text(heroCopy)
                .font(DS.Typography.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(theme.onSurface)
                .lineSpacing(4)
                .tracking(DS.Typography.headlineTracking)

            Text(pointsLine)
                .font(DS.Typography.captionBold)
                .foregroundColor(theme.onSurface.opacity(0.7))
        }
    }

    @ViewBuilder
    private func summarySection(theme: ThemeTokens) -> some View {
        if shouldShowSummary, !displayRows.isEmpty {
            feedbackContainer(theme: theme) {
                ForEach(Array(displayRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(row.title)
                            .font(DS.Typography.captionBold)
                            .foregroundColor(theme.onSurface)
                        styledFeedbackText(row.body, theme: theme)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func correctAnswerSection(theme: ThemeTokens) -> some View {
        if !feedback.isOpenEnded,
           !heroIsPositive,
           let answer = trimmed(feedback.correctAnswerDetail ?? feedback.correctAnswer) {
            feedbackContainer(theme: theme, title: "Correct answer") {
                styledFeedbackText(answer, theme: theme)
            }
        }
    }

    @ViewBuilder
    private func whySection(theme: ThemeTokens) -> some View {
        if let why = trimmedWhy {
            feedbackContainer(theme: theme, title: "Why") {
                styledFeedbackText(why, theme: theme)
            }
        } else if !feedback.isOpenEnded && feedback.isWhyPending {
            feedbackContainer(theme: theme, title: "Why") {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Fetching explanation…")
                        .font(DS.Typography.caption)
                        .foregroundColor(theme.onSurface.opacity(0.6))
                }
            }
        }
    }

    @ViewBuilder
    private func exemplarSection(theme: ThemeTokens) -> some View {
        if let exemplar = exemplarText {
            feedbackContainer(theme: theme, title: "10/10 answer") {
                styledFeedbackText(exemplar, theme: theme)
            }
        }
    }

    @ViewBuilder
    private func feedbackContainer(theme: ThemeTokens, title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let title = title {
                Text(title)
                    .font(DS.Typography.captionBold)
                    .foregroundColor(theme.onSurface)
            }
            content()
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.surfaceVariant)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.outline.opacity(0.25), lineWidth: 1)
        )
    }

    private func styledFeedbackText(_ text: String, theme: ThemeTokens) -> some View {
        Text(text)
            .font(DS.Typography.body)
            .foregroundColor(theme.onSurface.opacity(0.85))
            .lineSpacing(feedbackLineSpacing)
            .tracking(feedbackTracking)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private let barHeight: CGFloat = 8
    private let barCornerRadius: CGFloat = 4
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        let palette = themeManager.activeRoles
        let clampedProgress: Double = {
            guard progress.isFinite else { return 0 }
            return min(max(progress, 0), 1)
        }()
        let trackColor = palette.color(role: .neutral, tone: 90)
            ?? palette.color(role: .neutralVariant, tone: 90)
            ?? palette.color(role: .primary, tone: 90)
            ?? theme.surfaceVariant
        let fillColor = palette.color(role: .tertiary, tone: 40)
            ?? palette.color(role: .primary, tone: 40)
            ?? theme.tertiary

        GeometryReader { geometry in
            let width = max(0, geometry.size.width * clampedProgress)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                    .fill(trackColor)
                    .frame(height: barHeight)

                RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                    .fill(fillColor)
                    .frame(width: width, height: barHeight)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: barHeight)
    }
}

struct QuestionMetadataRow: View {
    let question: Question
    
    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            DifficultyBadge(difficulty: question.difficulty)
            
            Spacer()
            
            HStack(spacing: DS.Spacing.xs) {
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
    }
}

// MARK: - Badges

struct DifficultyBadge: View {
    let difficulty: QuestionDifficulty
    
    var body: some View {
        Text(difficulty.rawValue)
            .font(DS.Typography.caption)
            .foregroundStyle(colorForDifficulty)
            .padding(.horizontal, DS.Spacing.xs + 3)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(colorForDifficulty.opacity(0.12))
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
            .padding(.horizontal, DS.Spacing.xs + 3)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DS.Colors.secondaryText.opacity(0.08))
            )
    }
}

struct RetrievalBadge: View {
    var body: some View {
        Text("Retrieval")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Colors.secondaryText)
            .padding(.horizontal, DS.Spacing.xs + 3)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DS.Colors.secondaryText.opacity(0.08))
            )
            .accessibilityLabel("Retrieval")
    }
}

struct CurveballBadge: View {
    var body: some View {
        Text("CB")
            .font(DS.Typography.captionBold)
            .foregroundStyle(Color.black)
            .padding(.horizontal, DS.Spacing.xs + 3)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.yellow.opacity(0.9))
            )
            .overlay(
                Capsule()
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
            .padding(.horizontal, DS.Spacing.xs + 3)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.9))
            )
            .overlay(
                Capsule()
                    .stroke(Color.blue, lineWidth: DS.BorderWidth.thin)
            )
            .accessibilityLabel("Spaced Follow-up")
    }
}

// Shared primary button label for Check/Continue/Finish states
struct TestPrimaryButtonLabel: View {
    let text: String
    let isLoading: Bool
    
    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.white))
                    .scaleEffect(0.8)
            } else {
                Text(text)
                DSIcon("checkmark", size: 16)
            }
        }
        .font(DS.Typography.captionBold)
    }
}
