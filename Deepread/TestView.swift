import SwiftUI
import SwiftData

// MARK: - Question Feedback Model

struct QuestionFeedback {
    let isCorrect: Bool
    let correctAnswer: String?
    let explanation: String
    let pointsEarned: Int
    let maxPoints: Int
}

struct TestView: View {
    let idea: Idea
    let test: Test
    let openAIService: OpenAIService
    let onCompletion: (TestAttempt) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentQuestionIndex = 0
    @State private var responses: [UUID: String] = [:]
    @State private var selectedOptions: [UUID: Set<Int>] = [:]
    @State private var currentAttempt: TestAttempt?
    @State private var isSubmitting = false
    @State private var showingResults = false
    @State private var evaluationResult: TestEvaluationResult?
    
    // Immediate feedback states
    @State private var showingFeedback = false
    @State private var currentFeedback: QuestionFeedback?
    @State private var isEvaluatingQuestion = false
    @State private var questionEvaluations: [UUID: QuestionEvaluation] = [:]
    
    private var currentQuestion: Question? {
        test.orderedQuestions.indices.contains(currentQuestionIndex) ? test.orderedQuestions[currentQuestionIndex] : nil
    }
    
    private var progress: Double {
        Double(currentQuestionIndex) / Double(test.questions.count)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress Bar
                ProgressBar(progress: progress, currentQuestion: currentQuestionIndex + 1, totalQuestions: test.questions.count)
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
                                isDisabled: showingFeedback
                            )
                            .padding(DS.Spacing.lg)
                        }
                    }
                    
                    // Feedback Overlay
                    if showingFeedback, let feedback = currentFeedback {
                        FeedbackOverlay(feedback: feedback)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }
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
                        .dsSecondaryButton()
                    }
                    
                    Spacer()
                    
                    if currentQuestionIndex < test.questions.count - 1 {
                        if showingFeedback {
                            Button(action: nextQuestion) {
                                HStack(spacing: DS.Spacing.xs) {
                                    Text("Continue")
                                    DSIcon("chevron.right", size: 16)
                                }
                                .font(DS.Typography.captionBold)
                            }
                            .dsPrimaryButton()
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
                            .dsPrimaryButton()
                            .disabled(!isCurrentQuestionAnswered() || isEvaluatingQuestion)
                        }
                    } else {
                        if showingFeedback {
                            Button(action: submitTest) {
                                Text("Finish Test")
                                    .font(DS.Typography.captionBold)
                            }
                            .dsPrimaryButton()
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
                            .dsPrimaryButton()
                            .disabled(!isCurrentQuestionAnswered() || isEvaluatingQuestion)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            .background(DS.Colors.primaryBackground)
            .navigationTitle("Test: \(idea.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Exit") {
                        dismiss()
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.primaryText)
                }
            }
            .onAppear {
                initializeAttempt()
            }
            .sheet(isPresented: $showingResults) {
                if let result = evaluationResult, let attempt = currentAttempt {
                    TestResultsView(
                        idea: idea,
                        test: test,
                        attempt: attempt,
                        result: result,
                        onContinue: { attempt in
                            onCompletion(attempt)
                            dismiss()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func initializeAttempt() {
        let attempt = TestAttempt(testId: test.id)
        modelContext.insert(attempt)
        currentAttempt = attempt
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
        saveCurrentResponse()
        
        Task {
            do {
                // Evaluate the current question immediately
                let evaluation = try await evaluateCurrentQuestion(question)
                
                await MainActor.run {
                    self.questionEvaluations[question.id] = evaluation
                    self.currentFeedback = QuestionFeedback(
                        isCorrect: evaluation.isCorrect,
                        correctAnswer: evaluation.correctAnswer,
                        explanation: evaluation.feedback,
                        pointsEarned: evaluation.pointsEarned,
                        maxPoints: question.difficulty.pointValue
                    )
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        self.showingFeedback = true
                    }
                    self.isEvaluatingQuestion = false
                }
            } catch {
                print("Error evaluating question: \(error)")
                await MainActor.run {
                    self.isEvaluatingQuestion = false
                }
            }
        }
    }
    
    private func nextQuestion() {
        withAnimation {
            showingFeedback = false
            currentFeedback = nil
            currentQuestionIndex = min(currentQuestionIndex + 1, test.questions.count - 1)
        }
    }
    
    private func previousQuestion() {
        saveCurrentResponse()
        withAnimation {
            currentQuestionIndex = max(currentQuestionIndex - 1, 0)
        }
    }
    
    private func saveCurrentResponse() {
        guard let question = currentQuestion,
              let attempt = currentAttempt else { return }
        
        // Check if response already exists
        if let existingResponse = attempt.responses.first(where: { $0.questionId == question.id }) {
            // Update existing response
            updateResponse(existingResponse, for: question)
        } else {
            // Create new response
            createResponse(for: question, attempt: attempt)
        }
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
        
        modelContext.insert(response)
        attempt.responses.append(response)
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
                        if let response = attempt.responses.first(where: { $0.questionId == question.id }) {
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
                
                // Determine mastery
                let allCorrect = correctCount == test.questions.count
                if allCorrect {
                    if test.testType == "review" {
                        attempt.masteryAchieved = .solid
                    } else {
                        attempt.masteryAchieved = .fragile
                    }
                }
                
                // Save changes
                try modelContext.save()
                
                let result = TestEvaluationResult(
                    totalScore: totalScore,
                    maxScore: 125, // 3×10 (easy) + 3×15 (medium) + 2×25 (hard) = 30 + 45 + 50 = 125
                    correctCount: correctCount,
                    totalQuestions: test.questions.count,
                    masteryAchieved: attempt.masteryAchieved,
                    evaluationDetails: evaluationDetails
                )
                
                await MainActor.run {
                    evaluationResult = result
                    isSubmitting = false
                    showingResults = true
                }
            } catch {
                print("Error submitting test: \(error)")
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Question View Component

struct QuestionView: View {
    let question: Question
    let questionNumber: Int
    @Binding var response: String
    @Binding var selectedOptions: Set<Int>
    let isDisabled: Bool
    
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
                        BloomBadge(category: question.bloomCategory)
                    }
                }
                
                Spacer()
                
                Text("\(question.difficulty.pointValue) pts")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.tertiaryText)
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
                OpenEndedInput(response: $response, isDisabled: isDisabled)
            }
        }
    }
}

// MARK: - Option Components

struct MCQOptions: View {
    let options: [String]
    @Binding var selectedOptions: Set<Int>
    let isDisabled: Bool
    
    var body: some View {
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
                            .foregroundStyle(selectedOptions.contains(index) ? DS.Colors.primaryText : DS.Colors.tertiaryText)
                        
                        Text(option)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.primaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(
                        Rectangle()
                            .fill(selectedOptions.contains(index) ? DS.Colors.tertiaryBackground : DS.Colors.secondaryBackground)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedOptions.contains(index) ? DS.Colors.primaryText : DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Select all that apply")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.secondaryText)
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
                            .foregroundStyle(selectedOptions.contains(index) ? DS.Colors.primaryText : DS.Colors.tertiaryText)
                        
                        Text(option)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.primaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(
                        Rectangle()
                            .fill(selectedOptions.contains(index) ? DS.Colors.tertiaryBackground : DS.Colors.secondaryBackground)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedOptions.contains(index) ? DS.Colors.primaryText : DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Your response (2-4 sentences)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.secondaryText)
            
            TextEditor(text: $response)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .frame(minHeight: 120)
                .padding(DS.Spacing.md)
                .background(
                    Rectangle()
                        .fill(DS.Colors.tertiaryBackground)
                        .overlay(
                            Rectangle()
                                .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
                        )
                )
                .disabled(isDisabled)
        }
    }
}

// MARK: - Feedback Overlay

struct FeedbackOverlay: View {
    let feedback: QuestionFeedback
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { }  // Prevent taps from going through
                
                // Feedback content positioned at bottom
                VStack {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                        // Result Header
                        HStack(spacing: DS.Spacing.md) {
                            // Icon
                            DSIcon(
                                feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill",
                                size: 32
                            )
                            .foregroundStyle(feedback.isCorrect ? .green : .red)
                            
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(feedback.isCorrect ? "Correct!" : "Incorrect")
                                    .font(DS.Typography.bodyBold)
                                    .foregroundStyle(DS.Colors.primaryText)
                                
                                Text("\(feedback.pointsEarned)/\(feedback.maxPoints) points")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.secondaryText)
                            }
                            
                            Spacer()
                        }
                        
                        // Explanation
                        if !feedback.explanation.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Explanation")
                                    .font(DS.Typography.captionBold)
                                    .foregroundStyle(DS.Colors.primaryText)
                                
                                Text(feedback.explanation)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.secondaryText)
                            }
                        }
                        
                        // Correct Answer (if incorrect)
                        if !feedback.isCorrect, let correctAnswer = feedback.correctAnswer {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Correct Answer")
                                    .font(DS.Typography.captionBold)
                                    .foregroundStyle(DS.Colors.primaryText)
                                
                                Text(correctAnswer)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.secondaryText)
                            }
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .background(
                        Rectangle()
                            .fill(feedback.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .overlay(
                                Rectangle()
                                    .stroke(feedback.isCorrect ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: DS.BorderWidth.medium)
                            )
                    )
                    .cornerRadius(12)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
                }
            }
        }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double
    let currentQuestion: Int
    let totalQuestions: Int
    
    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack {
                Text("Question \(currentQuestion) of \(totalQuestions)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.secondaryText)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(DS.Colors.primaryText)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(DS.Colors.tertiaryBackground)
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(DS.Colors.primaryText)
                        .frame(width: geometry.size.width * progress, height: 4)
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