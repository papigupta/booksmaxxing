import SwiftUI
import SwiftData

struct TestResultsView: View {
    let idea: Idea
    let test: Test
    let attempt: TestAttempt
    let result: TestEvaluationResult
    let onContinue: (TestAttempt) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingRetryTest = false
    @State private var retryTest: Test?
    @State private var isGeneratingRetryTest = false
    
    private var hasIncorrectAnswers: Bool {
        !result.incorrectQuestions.isEmpty
    }
    
    private var masteryAchieved: Bool {
        result.masteryAchieved != .none
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Header with score
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        Text("Test Complete!")
                            .font(DS.Typography.largeTitle)
                            .foregroundStyle(DS.Colors.primaryText)
                        
                        // Score display
                        HStack(spacing: DS.Spacing.md) {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Score")
                                    .font(DS.Typography.captionBold)
                                    .foregroundStyle(DS.Colors.secondaryText)
                                Text("\(result.totalScore)/\(result.maxScore)")
                                    .font(DS.Typography.title)
                                    .foregroundStyle(DS.Colors.primaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Accuracy")
                                    .font(DS.Typography.captionBold)
                                    .foregroundStyle(DS.Colors.secondaryText)
                                Text("\(result.correctCount)/\(result.totalQuestions)")
                                    .font(DS.Typography.title)
                                    .foregroundStyle(DS.Colors.primaryText)
                            }
                            
                            Spacer()
                            
                            // Mastery badge (only show for solid mastery)
                            if result.masteryAchieved == .solid {
                                VStack(alignment: .center, spacing: DS.Spacing.xs) {
                                    DSIcon("star.fill", size: 24)
                                        .foregroundStyle(.yellow)
                                    Text("SOLID MASTERY")
                                        .font(DS.Typography.captionBold)
                                        .foregroundStyle(DS.Colors.primaryText)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .padding(DS.Spacing.lg)
                        .background(
                            Rectangle()
                                .fill(DS.Colors.tertiaryBackground)
                                .overlay(
                                    Rectangle()
                                        .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
                                )
                        )
                    }
                    
                    // Results breakdown
                    if !result.evaluationDetails.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            Text("Question Breakdown")
                                .font(DS.Typography.bodyBold)
                                .foregroundStyle(DS.Colors.primaryText)
                            
                            ForEach(Array(result.evaluationDetails.enumerated()), id: \.element.questionId) { index, evaluation in
                                QuestionResultCard(
                                    questionNumber: index + 1,
                                    evaluation: evaluation,
                                    question: test.questions.first { $0.id == evaluation.questionId }
                                )
                            }
                        }
                    }
                    
                    // Incorrect answers summary (if any)
                    if hasIncorrectAnswers {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            HStack {
                                DSIcon("exclamationmark.triangle.fill", size: 20)
                                    .foregroundStyle(.orange)
                                Text("Areas to Review")
                                    .font(DS.Typography.bodyBold)
                                    .foregroundStyle(DS.Colors.primaryText)
                            }
                            
                            Text("You got \(result.incorrectQuestions.count) question\(result.incorrectQuestions.count == 1 ? "" : "s") incorrect. Let's focus on those concepts!")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.secondaryText)
                        }
                        .padding(DS.Spacing.md)
                        .background(
                            Rectangle()
                                .fill(.orange.opacity(0.1))
                                .overlay(
                                    Rectangle()
                                        .stroke(.orange.opacity(0.3), lineWidth: DS.BorderWidth.thin)
                                )
                        )
                    }
                    
                    // Next steps
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        Text("What's Next?")
                            .font(DS.Typography.bodyBold)
                            .foregroundStyle(DS.Colors.primaryText)
                        
                        if hasIncorrectAnswers {
                            Text("Review the incorrect answers and try again to achieve mastery.")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.secondaryText)
                        } else if result.masteryAchieved == .solid {
                            Text("Perfect! You've achieved solid mastery of this idea.")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.secondaryText)
                        } else {
                            Text("Great job! Keep practicing to solidify your understanding.")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.secondaryText)
                        }
                    }
                }
                .padding(DS.Spacing.lg)
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.primaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DS.Spacing.md) {
                    DSDivider()
                    
                    HStack(spacing: DS.Spacing.md) {
                        if hasIncorrectAnswers {
                            Button(action: generateRetryTest) {
                                HStack(spacing: DS.Spacing.xs) {
                                    if isGeneratingRetryTest {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.white))
                                            .scaleEffect(0.8)
                                    } else {
                                        DSIcon("arrow.clockwise", size: 16)
                                            .foregroundStyle(DS.Colors.white)
                                    }
                                    Text(isGeneratingRetryTest ? "Preparing..." : "Retry Incorrect")
                                        .font(DS.Typography.captionBold)
                                        .foregroundStyle(DS.Colors.white)
                                }
                            }
                            .dsPrimaryButton()
                            .disabled(isGeneratingRetryTest)
                        }
                        
                        Button(action: completeTest) {
                            Text(hasIncorrectAnswers ? "Continue Anyway" : "Continue")
                                .font(DS.Typography.captionBold)
                        }
                        .dsSecondaryButton()
                        
                        if !hasIncorrectAnswers {
                            Spacer()
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
                .background(DS.Colors.primaryBackground)
            }
            .sheet(isPresented: $showingRetryTest) {
                if let retryTest = retryTest {
                    TestView(
                        idea: idea,
                        test: retryTest,
                        openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey),
                        onCompletion: { newAttempt, _ in
                            // After retry, show results again
                            showingRetryTest = false
                            Task {
                                // Update attempt with retry results
                                try await handleRetryCompletion(newAttempt)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateRetryTest() {
        isGeneratingRetryTest = true
        
        Task {
            do {
                let testGenerationService = TestGenerationService(
                    openAI: OpenAIService(apiKey: Secrets.openAIAPIKey),
                    modelContext: modelContext
                )
                
                // Get incorrect responses for focused retry
                let incorrectResponses = attempt.incorrectResponses
                
                // Generate retry test with focus on mistakes
                let newRetryTest = try await testGenerationService.generateRetryTest(
                    for: idea,
                    incorrectResponses: incorrectResponses
                )
                
                await MainActor.run {
                    self.retryTest = newRetryTest
                    self.isGeneratingRetryTest = false
                    self.showingRetryTest = true
                }
            } catch {
                print("Error generating retry test: \(error)")
                await MainActor.run {
                    self.isGeneratingRetryTest = false
                    // Could show error alert here
                }
            }
        }
    }
    
    private func handleRetryCompletion(_ retryAttempt: TestAttempt) async throws {
        // Update attempt retry count
        attempt.retryCount += 1
        
        // If all answers are now correct, update mastery
        if retryAttempt.incorrectResponses.isEmpty {
            if test.testType == "review" {
                attempt.masteryAchieved = .solid
            } else {
                // No 'fragile' mastery; do not schedule a review here
                attempt.masteryAchieved = .none
            }
        }
        
        try modelContext.save()
        
        // Update the idea's coverage (will be updated through the lesson system)
        // Coverage is tracked per question type answered correctly
        
        // Dismiss and continue
        await MainActor.run {
            completeTest()
        }
    }
    
    // Removed fragile mastery scheduling; review/curveballs manage consolidation
    
    private func updateIdeaCoverage() {
        // Coverage is now tracked through CoverageService based on question types answered
        // This function is kept for compatibility but coverage is updated elsewhere
        idea.lastPracticed = Date()
    }
    
    private func completeTest() {
        // Mistake queueing is owned by the lesson flow (DailyPracticeView)
        updateIdeaCoverage()
        onContinue(attempt)
    }
}

// MARK: - Question Result Card

struct QuestionResultCard: View {
    let questionNumber: Int
    let evaluation: QuestionEvaluation
    let question: Question?
    
    private var isCorrect: Bool {
        evaluation.isCorrect
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                // Question number
                Text("Q\(questionNumber)")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(DS.Colors.secondaryText)
                    .frame(width: 30, alignment: .leading)
                
                // Result icon
                DSIcon(
                    isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill",
                    size: 20
                )
                .foregroundStyle(isCorrect ? .green : .red)
                
                // Question type and difficulty (+ CB badge if curveball)
                if let question = question {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(question.type.rawValue)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.tertiaryText)
                        
                        Text("•")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.tertiaryText)
                        
                        Text(question.difficulty.rawValue)
                            .font(DS.Typography.caption)
                            .foregroundStyle(difficultyColor(question.difficulty))
                        
                        if question.isCurveball {
                            Text("CB")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.9))
                                .cornerRadius(3)
                        }
                    }
                }
                
                Spacer()
                
                // Points earned
                Text("\(evaluation.pointsEarned) pts")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(DS.Colors.primaryText)
            }
            
            // Feedback
            if !evaluation.feedback.isEmpty {
                Text(evaluation.feedback)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.secondaryText)
            }
        }
        .padding(DS.Spacing.md)
        .background(
            Rectangle()
                .fill(isCorrect ? .green.opacity(0.05) : .red.opacity(0.05))
                .overlay(
                    Rectangle()
                        .stroke(isCorrect ? .green.opacity(0.2) : .red.opacity(0.2), lineWidth: DS.BorderWidth.thin)
                )
        )
    }
    
    private func difficultyColor(_ difficulty: QuestionDifficulty) -> Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}
