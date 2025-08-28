import SwiftUI
import SwiftData

struct DailyPracticeView: View {
    let book: Book
    let openAIService: OpenAIService
    let practiceType: PracticeType
    let onPracticeComplete: (() -> Void)?
    
    init(book: Book, openAIService: OpenAIService, practiceType: PracticeType, onPracticeComplete: (() -> Void)? = nil) {
        self.book = book
        self.openAIService = openAIService
        self.practiceType = practiceType
        self.onPracticeComplete = onPracticeComplete
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isGenerating = true
    @State private var generatedTest: Test?
    @State private var errorMessage: String?
    @State private var showingTest = false
    @State private var completedAttempt: TestAttempt?
    @State private var currentView: PracticeFlowState = .none
    
    enum PracticeFlowState {
        case none
        case results
        case streak
    }
    
    private var practiceGenerator: PracticeGenerator {
        PracticeGenerator(
            modelContext: modelContext,
            openAIService: openAIService,
            configuration: PracticeConfiguration.configuration(for: practiceType)
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
                        idea: Idea(
                            id: "daily_practice",
                            title: "Daily Practice",
                            description: "Mixed practice from \(book.title)",
                            bookTitle: book.title,
                            depthTarget: 3
                        ),
                        test: test,
                        openAIService: openAIService,
                        onCompletion: handleTestCompletion
                    )
                }
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
                        print("DEBUG: Streak onContinue tapped, going back to homepage")
                        currentView = .none
                        onPracticeComplete?() // Advance milestone
                        dismiss() // Go back to homepage
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
                
                Text("Generating Your Practice Session")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.black)
                
                Text("Selecting the perfect mix of new and review questions...")
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
            let test = try practiceGenerator.generateDailyPractice(for: book, type: practiceType)
            
            await MainActor.run {
                self.generatedTest = test
                self.isGenerating = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
    
    private func handleTestCompletion(_ attempt: TestAttempt) {
        completedAttempt = attempt
        showingTest = false
        
        // Update progress for all ideas in the practice
        if let test = generatedTest {
            practiceGenerator.updateProgressAfterPractice(attempt: attempt, practiceTest: test)
        }
        
        // Show results with a small delay to ensure proper state transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("DEBUG: Setting currentView to .results")
            currentView = .results
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