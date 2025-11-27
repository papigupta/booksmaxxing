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
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingRetryTest = false
    @State private var retryTest: Test?
    @State private var isGeneratingRetryTest = false
    
    private var hasIncorrectAnswers: Bool {
        !result.incorrectQuestions.isEmpty
    }
    
    private var masteryAchieved: Bool {
        result.masteryAchieved != .none
    }

    private var accuracyPercentage: Int {
        guard result.totalQuestions > 0 else { return 0 }
        let ratio = (Double(result.correctCount) / Double(result.totalQuestions)) * 100
        return Int(ratio.rounded())
    }
    
    private var correctOutOfTotalText: String {
        "\(result.correctCount)/\(result.totalQuestions) correct"
    }
    
    private var incorrectSummaryText: String {
        let count = result.incorrectQuestions.count
        let questionWord = count == 1 ? "question" : "questions"
        return "You missed \(count) \(questionWord) this round. We'll bring those ideas back in your next lessons so you can lock them in."
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Score display
                    HStack(spacing: DS.Spacing.xl) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Clarity")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                            Text("\(accuracyPercentage)%")
                                .font(DS.Typography.title)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                        }

                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Correct")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text("\(result.correctCount)")
                                    .font(DS.Typography.title)
                                    .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                                Text("/\(result.totalQuestions)")
                                    .font(DS.Typography.captionBold)
                                    .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                            }
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
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(themeManager.currentTokens(for: colorScheme).surfaceVariant)
                    )
                    
                    // Results breakdown
                    if !result.evaluationDetails.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            Text("Question Breakdown")
                                .font(DS.Typography.bodyBold)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                            
                            ForEach(Array(result.evaluationDetails.enumerated()), id: \.element.questionId) { index, evaluation in
                                QuestionResultCard(
                                    questionNumber: index + 1,
                                    evaluation: evaluation,
                                    question: (test.questions ?? []).first { $0.id == evaluation.questionId }
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
                                    .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                            }
                            
                            Text(incorrectSummaryText)
                                .font(DS.Typography.body)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                        }
                        .padding(DS.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.orange.opacity(0.12))
                        )
                    }
                }
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.lg)
            }
            .background(themeManager.currentTokens(for: colorScheme).surface)
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
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
                                            .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTokens(for: colorScheme).onSurface))
                                            .scaleEffect(0.8)
                                    } else {
                                        DSIcon("arrow.clockwise", size: 16)
                                            .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                                    }
                                    Text(isGeneratingRetryTest ? "Preparing..." : "Retry Incorrect")
                                        .font(DS.Typography.captionBold)
                                        .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isGeneratingRetryTest)
                        }
                        
                        Spacer()
                        
                        Button(action: completeTest) {
                            TestPrimaryButtonLabel(text: hasIncorrectAnswers ? "Continue Anyway" : "Continue", isLoading: false)
                        }
                        .dsPalettePrimaryButton()
                    }
                    .padding(.horizontal, DS.Spacing.xxl)
                    .padding(.vertical, DS.Spacing.md)
                }
                .background(themeManager.currentTokens(for: colorScheme).surface)
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
        .background(themeManager.currentTokens(for: colorScheme).surface.ignoresSafeArea())
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
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCorrect: Bool {
        evaluation.isCorrect
    }
    
    private var statusLabel: (text: String, color: Color) {
        guard let q = question else { return (evaluation.isCorrect ? "On Track" : "Off Track", evaluation.isCorrect ? .green : .red) }
        let ratio = q.difficulty.pointValue > 0 ? Double(evaluation.pointsEarned) / Double(q.difficulty.pointValue) : 0
        switch ratio {
        case let r where r >= 0.70: return ("On Track", .green)
        case let r where r >= 0.50: return ("Close", .orange)
        default: return ("Off Track", .red)
        }
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
        let normalized = normalize(evaluation.feedback)
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

    @State private var showExemplar: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                // Question number
                Text("Q\(questionNumber)")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(DS.Colors.secondaryText)
                    .frame(width: 30, alignment: .leading)
                
                // Result icon
                if question?.type == .openEnded {
                    DSIcon("lightbulb.fill", size: 18).foregroundStyle(.yellow)
                } else {
                    DSIcon(isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill", size: 20)
                        .foregroundStyle(isCorrect ? .green : .red)
                }
                
                // Question type and difficulty (+ CB badge if curveball)
                if let question = question {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(question.type.rawValue)
                            .font(DS.Typography.caption)
                            .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.6))
                        
                        Text("•")
                            .font(DS.Typography.caption)
                            .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.6))
                        
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
                        } else if question.isSpacedFollowUp {
                            Text("SPFU")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.9))
                                .cornerRadius(3)
                        }
                    }
                }
                
                Spacer()
                
                // Status + points
                HStack(spacing: DS.Spacing.sm) {
                    Text(statusLabel.text)
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(statusLabel.color)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(statusLabel.color.opacity(0.15))
                        )
                    Text("\(evaluation.pointsEarned) pts")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                }
            }
            
            // Feedback (formatted)
            if !evaluation.feedback.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(Array(displayRows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(row.title)
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                    Text(row.body)
                        .font(DS.Typography.caption)
                        .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                    }
                }
            }

            // Exemplar for OEQ in results list (collapsed)
            if (question?.type == .openEnded), let exemplar = evaluation.correctAnswer, !exemplar.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themeManager.currentTokens(for: colorScheme).surfaceVariant)
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
