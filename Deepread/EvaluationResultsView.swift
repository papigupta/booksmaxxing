import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let prompt: String // Add prompt parameter
    let level: Int
    let onOpenPrimer: () -> Void // Add callback for parent to handle primer navigation
    
    @Environment(\.modelContext) private var modelContext
    @State private var evaluationResult: EvaluationResult?
    @State private var isLoadingEvaluation = true
    @State private var evaluationError: String?
    @State private var isSavingResponse = false
    @State private var navigateToWhatThisMeans = false
    @State private var isResponseExpanded = false
    @State private var navigateToHome = false
    @State private var showingPrimer = false // Add this line
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
        let maxLength = 100
        if userResponse.count <= maxLength {
            return userResponse
        }
        let truncated = String(userResponse.prefix(maxLength))
        return truncated + "..."
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoadingEvaluation {
                VStack(spacing: 32) {
                    Spacer()
                    
                    Text("Level scanner in progress")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 16) {
                        let loadingSteps = [
                            ("Scouting for hidden insights", "🔍"),
                            ("Weighing depth vs. detail", "⚖️"),
                            ("Sorting you onto the mastery ladder", "🪜")
                        ]
                        
                        ForEach(0..<loadingSteps.count, id: \.self) { index in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 8, height: 8)
                                
                                Text("\(loadingSteps[index].0) \(loadingSteps[index].1)")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    Text("Almost there—loading challenges that match your power-ups")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .padding()
            } else if let error = evaluationError {
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Evaluation Error")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        loadEvaluation()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
            } else if let result = evaluationResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Book title
                        Text(idea.bookTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                        
                        // Idea title
                        Text(idea.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 24)
                        
                        // Score section
                        VStack(spacing: 16) {
                            HStack {
                                Text("Your Score")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(result.score10)/10")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                            }
                            
                            // Progress bar
                            ProgressView(value: Double(result.score10), total: 10.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        }
                        .padding(.horizontal, 24)
                        
                        // Response section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Your Response")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(action: {
                                    isResponseExpanded.toggle()
                                }) {
                                    Text(isResponseExpanded ? "Show Less" : "Show More")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                            
                            Text(isResponseExpanded ? userResponse : truncatedResponse)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 24)
                        

                        
                        // Structured Author Feedback
                        if isLoadingStructuredFeedback {
                            VStack(spacing: 12) {
                                ProgressView().scaleEffect(0.8)
                                Text("Generating personalized feedback...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 24)
                        } else if let fb = authorFeedback {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Author's Insight")
                                    .font(.headline)
                                    .fontWeight(.semibold)

                                Text(fb.verdict)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("One Big Thing").font(.subheadline).fontWeight(.semibold)
                                    Text(fb.oneBigThing)
                                        .font(.body)
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }

                                if !fb.evidence.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Receipts").font(.subheadline).fontWeight(.semibold)
                                        ForEach(fb.evidence, id: \.self) { q in
                                            Text("\"\(q)\"").font(.callout).foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if !fb.upgrade.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Upgrade (try this rewrite)").font(.subheadline).fontWeight(.semibold)
                                        Text(fb.upgrade)
                                            .font(.body)
                                            .padding()
                                            .background(Color(.systemGray6))
                                            .cornerRadius(8)
                                    }
                                }

                                if !fb.transferCue.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Transfer Cue").font(.subheadline).fontWeight(.semibold)
                                        Text(fb.transferCue).font(.body)
                                    }
                                }

                                if !fb.microDrill.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("60-sec Drill").font(.subheadline).fontWeight(.semibold)
                                        Text(fb.microDrill).font(.body)
                                    }
                                }

                                if !fb.memoryHook.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Memory Hook").font(.subheadline).fontWeight(.semibold)
                                        Text(fb.memoryHook)
                                            .font(.headline) // slightly stronger
                                    }
                                }

                                if let trap = fb.edgeOrTrap, !trap.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Edge/Trap").font(.subheadline).fontWeight(.semibold)
                                        Text(trap).font(.body)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        // Primer CTA for failed responses
                        if !result.pass {
                            VStack(spacing: 16) {
                                Text("Need a refresher?")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                
                                Button(action: {
                                    onOpenPrimer()
                                }) {
                                    HStack {
                                        Image(systemName: "lightbulb")
                                            .font(.title3)
                                        Text("Open Primer")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundStyle(.white)
                                    .cornerRadius(12)
                                }
                                
                                Text("Review the core concepts before continuing")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        // Continue button
                        VStack(spacing: 16) {
                            Button(action: {
                                saveResponseAndContinue()
                            }) {
                                HStack {
                                    if isSavingResponse {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .foregroundStyle(.white)
                                    } else {
                                        Text("Continue")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                            .disabled(isSavingResponse)
                            
                            Text("Your response and evaluation will be saved")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true) // Hide the back button
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    navigateToHome = true
                }) {
                    Image(systemName: "text.book.closed")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Go to home")
                .accessibilityHint("Return to all extracted ideas")
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingPrimer = true
                }) {
                    Image(systemName: "lightbulb")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("View Primer")
                .accessibilityHint("Open primer for this idea")
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
                let savedResponse = try await userResponseService.saveUserResponseWithEvaluation(
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