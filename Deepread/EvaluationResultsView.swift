import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let prompt: String
    let level: Int
    let onOpenPrimer: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var evaluationResult: EvaluationResult?
    @State private var isLoadingEvaluation = true
    @State private var evaluationError: String?
    @State private var isSavingResponse = false
    @State private var navigateToWhatThisMeans = false
    @State private var isResponseExpanded = false
    @State private var navigateToHome = false
    @State private var showingPrimer = false
    @State private var authorFeedback: AuthorFeedback? = nil
    @State private var isLoadingStructuredFeedback = false
    @State private var structuredFeedbackError: String? = nil
    
    private var evaluationService: EvaluationService {
        EvaluationService(apiKey: Secrets.openAIAPIKey)
    }
    
    private var userResponseService: UserResponseService {
        UserResponseService(modelContext: modelContext)
    }
    
    private var truncatedResponse: String {
        let maxLength = 120
        if userResponse.count <= maxLength {
            return userResponse
        }
        let truncated = String(userResponse.prefix(maxLength))
        return truncated + "..."
    }
    
    // MARK: - Color Scheme
    private var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var successGradient: LinearGradient {
        LinearGradient(
            colors: [Color.green, Color.green.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var orangeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.orange, Color.orange.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    private var subtleBackground: Color {
        colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
    }
    
    var body: some View {
        ZStack {
            // Background
            subtleBackground
                .ignoresSafeArea()
            
            if isLoadingEvaluation {
                loadingView
            } else if let error = evaluationError {
                errorView(error)
            } else if let result = evaluationResult {
                evaluationContentView(result)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                homeButton
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                primerButton
            }
        }
        .navigationDestination(isPresented: $navigateToWhatThisMeans) {
            if let result = evaluationResult {
                WhatThisMeansView(
                    idea: idea,
                    evaluationResult: result,
                    userResponse: userResponse,
                    level: level,
                    openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
                )
            }
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey), bookService: BookService(modelContext: modelContext))
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey))
        }
        .onAppear {
            loadEvaluation()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Animated loading icon
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(primaryGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoadingEvaluation)
            }
            
            VStack(spacing: 24) {
                Text("Analyzing Your Response")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 20) {
                    let loadingSteps = [
                        ("Scouting for hidden insights", "🔍"),
                        ("Weighing depth vs. detail", "⚖️"),
                        ("Sorting you onto the mastery ladder", "🪜")
                    ]
                    
                    ForEach(0..<loadingSteps.count, id: \.self) { index in
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            
                            Text(loadingSteps[index].0)
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(loadingSteps[index].1)
                                .font(.title2)
                        }
                        .padding(.horizontal, 32)
                    }
                }
                
                Text("Almost there—loading challenges that match your power-ups")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                }
                
                VStack(spacing: 16) {
                    Text("Evaluation Error")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Button(action: { loadEvaluation() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(primaryGradient)
                    .cornerRadius(12)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Main Evaluation Content
    private func evaluationContentView(_ result: EvaluationResult) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Section
                headerSection(result)
                
                // Score Section
                scoreSection(result)
                
                // Response Section
                responseSection
                
                // Feedback Section
                if let fb = authorFeedback {
                    feedbackSection(fb)
                } else if isLoadingStructuredFeedback {
                    feedbackLoadingSection
                }
                
                // Action Section
                actionSection(result)
            }
        }
        .background(subtleBackground)
    }
    
    // MARK: - Header Section
    private func headerSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: 20) {
            // Book title
            Text(idea.bookTitle)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.top, 24)
            
            // Idea title
            Text(idea.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Level indicator
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                
                Text("Level \(level)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(cardBackground)
            .cornerRadius(20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    // MARK: - Score Section
    private func scoreSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: 24) {
            // Score display
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Score")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Text("\(result.score10) out of 10")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(result.pass ? .green : .orange)
                    }
                    
                    Spacer()
                    
                    // Score badge
                    ZStack {
                        Circle()
                            .fill(result.pass ? successGradient : orangeGradient)
                            .frame(width: 80, height: 80)
                        
                        VStack(spacing: 2) {
                            Text("\(result.score10)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            
                            Text("/10")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                
                // Progress bar
                VStack(spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((Double(result.score10) / 10.0) * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: Double(result.score10), total: 10.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: result.pass ? .green : .orange))
                        .scaleEffect(y: 2)
                }
            }
            
            // Pass/Fail indicator
            HStack(spacing: 12) {
                Image(systemName: result.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(result.pass ? .green : .orange)
                
                Text(result.pass ? "Level Complete!" : "Level Incomplete")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(result.pass ? .green : .orange)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                (result.pass ? Color.green : Color.orange).opacity(0.1)
            )
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    // MARK: - Response Section
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Response")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { isResponseExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Text(isResponseExpanded ? "Show Less" : "Show More")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Image(systemName: isResponseExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
            
            Text(isResponseExpanded ? userResponse : truncatedResponse)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(20)
                .background(subtleBackground)
                .cornerRadius(12)
                .animation(.easeInOut(duration: 0.3), value: isResponseExpanded)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    // MARK: - Feedback Loading Section
    private var feedbackLoadingSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text("Generating personalized feedback...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }
    
    // MARK: - Feedback Section
    private func feedbackSection(_ feedback: AuthorFeedback) -> some View {
        VStack(spacing: 24) {
            // Section header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                
                Text("Author's Insight")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            
            // Feedback cards
            LazyVStack(spacing: 16) {
                // Verdict card
                feedbackCard(
                    title: "Verdict",
                    content: feedback.verdict,
                    icon: "checkmark.shield.fill",
                    color: .blue
                )
                
                // One Big Thing card
                feedbackCard(
                    title: "One Big Thing",
                    content: feedback.oneBigThing,
                    icon: "star.fill",
                    color: .yellow
                )
                
                // Evidence card
                if !feedback.evidence.isEmpty {
                    feedbackCard(
                        title: "Evidence",
                        content: feedback.evidence.joined(separator: "\n\n"),
                        icon: "doc.text.fill",
                        color: .green
                    )
                }
                
                // Upgrade card
                if !feedback.upgrade.isEmpty {
                    feedbackCard(
                        title: "Upgrade Suggestion",
                        content: feedback.upgrade,
                        icon: "arrow.up.circle.fill",
                        color: .purple
                    )
                }
                
                // Transfer Cue card
                if !feedback.transferCue.isEmpty {
                    feedbackCard(
                        title: "Transfer Cue",
                        content: feedback.transferCue,
                        icon: "arrow.triangle.branch",
                        color: .orange
                    )
                }
                
                // Micro Drill card
                if !feedback.microDrill.isEmpty {
                    feedbackCard(
                        title: "60-Second Drill",
                        content: feedback.microDrill,
                        icon: "timer",
                        color: .red
                    )
                }
                
                // Memory Hook card
                if !feedback.memoryHook.isEmpty {
                    feedbackCard(
                        title: "Memory Hook",
                        content: feedback.memoryHook,
                        icon: "brain.head.profile",
                        color: .indigo
                    )
                }
                
                // Edge/Trap card
                if let trap = feedback.edgeOrTrap, !trap.isEmpty {
                    feedbackCard(
                        title: "Edge Case / Trap",
                        content: trap,
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }
    
    // MARK: - Feedback Card Helper
    private func feedbackCard(title: String, content: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            Text(content)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(nil)
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Action Section
    private func actionSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: 20) {
            // Primer CTA for failed responses
            if !result.pass {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Need a refresher?")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("Review the core concepts before continuing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Button(action: { onOpenPrimer() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.title3)
                            Text("Open Primer")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange.gradient)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(20)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal, 24)
            }
            
            // Continue button
            VStack(spacing: 12) {
                Button(action: { saveResponseAndContinue() }) {
                    HStack(spacing: 8) {
                        if isSavingResponse {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.title3)
                        }
                        
                        Text(isSavingResponse ? "Saving..." : "Continue")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(primaryGradient)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isSavingResponse)
                
                Text("Your response and evaluation will be saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Toolbar Buttons
    private var homeButton: some View {
        Button(action: { navigateToHome = true }) {
            Image(systemName: "text.book.closed")
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Go to home")
        .accessibilityHint("Return to all extracted ideas")
    }
    
    private var primerButton: some View {
        Button(action: { showingPrimer = true }) {
            Image(systemName: "lightbulb")
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("View Primer")
        .accessibilityHint("Open primer for this idea")
    }
    
    // MARK: - Private Methods
    
    private func loadEvaluation() {
        isLoadingEvaluation = true
        evaluationError = nil
        Task {
            do {
                let result = try await evaluationService.evaluateSubmission(
                    idea: idea,
                    userResponse: userResponse,
                    level: level
                )
                await MainActor.run {
                    self.evaluationResult = result
                    self.isLoadingEvaluation = false
                }
                
                // Load structured feedback after evaluation
                await loadStructuredFeedback(result: result)
            } catch {
                await MainActor.run {
                    let errorMessage = getErrorMessage(for: error)
                    self.evaluationError = errorMessage
                    self.isLoadingEvaluation = false
                }
            }
        }
    }
    
    private func loadStructuredFeedback(result: EvaluationResult) async {
        isLoadingStructuredFeedback = true
        do {
            let fb = try await evaluationService.generateStructuredFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: result
            )
            await MainActor.run {
                self.authorFeedback = fb
                self.isLoadingStructuredFeedback = false
            }
        } catch {
            await MainActor.run {
                self.structuredFeedbackError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.authorFeedback = nil
                self.isLoadingStructuredFeedback = false
            }
        }
    }
    
    private func saveResponseAndContinue() {
        guard let result = evaluationResult else { return }
        
        isSavingResponse = true
        
        Task {
            do {
                // Save the user response with evaluation
                _ = try await userResponseService.saveUserResponseWithEvaluation(
                    ideaId: idea.id,
                    level: level,
                    prompt: prompt,
                    response: userResponse,
                    evaluation: result
                )
                
                await MainActor.run {
                    isSavingResponse = false
                    navigateToWhatThisMeans = true
                }
            } catch {
                await MainActor.run {
                    isSavingResponse = false
                    evaluationError = "Failed to save response: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getErrorMessage(for error: Error) -> String {
        if let evaluationError = error as? EvaluationError {
            switch evaluationError {
            case .networkError:
                return "Network connection issue. Please check your internet connection and try again."
            case .timeout:
                return "Request timed out. Please try again - this usually resolves on retry."
            case .rateLimitExceeded:
                return "Service is busy right now. Please wait a moment and try again."
            case .serverError(let code):
                return "Server error (\(code)). Please try again in a moment."
            case .noResponse:
                return "No response received. Please try again."
            case .decodingError:
                return "Response format error. Please try again."
            case .invalidResponse:
                return "Invalid response from server. Please try again."
            case .invalidEvaluationFormat:
                return "Evaluation format error. Please try again."
            }
        }
        
        // Fallback for other errors
        return "Failed to evaluate response: \(error.localizedDescription)"
    }
}

#Preview {
    NavigationStack {
        EvaluationResultsView(
            idea: Idea(
                id: "i1",
                title: "Norman Doors",
                description: "The mind fills in blanks. But what if the blanks are the most important part?",
                bookTitle: "The Design of Everyday Things",
                depthTarget: 2,
                masteryLevel: 0,
                lastPracticed: nil,
                currentLevel: nil
            ),
            userResponse: "This is my response about Norman Doors...",
            prompt: "What is the design principle behind Norman Doors?",
            level: 0,
            onOpenPrimer: {}
        )
    }
} 