import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let prompt: String // Add prompt parameter
    let level: Int
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @State private var evaluationResult: EvaluationResult?
    @State private var contextAwareFeedback: String = ""
    @State private var isLoadingEvaluation = true
    @State private var isLoadingFeedback = false
    @State private var evaluationError: String?
    @State private var isSavingResponse = false
    @State private var navigateToWhatThisMeans = false
    @State private var isResponseExpanded = false
    @State private var navigateToHome = false
    
    private var evaluationService: EvaluationService {
        EvaluationService(openAIService: openAIService)
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
                        
                        // Strengths section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Strengths")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(result.strengths, id: \.self) { strength in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                        Text(strength)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Areas for improvement
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Areas for Improvement")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(result.improvements, id: \.self) { improvement in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        Text(improvement)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Context-aware feedback
                        if isLoadingFeedback {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating personalized feedback...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 24)
                        } else if !contextAwareFeedback.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Author's Insight")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text(contextAwareFeedback)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
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
        }
        .navigationDestination(isPresented: $navigateToWhatThisMeans) {
            if let result = evaluationResult {
                WhatThisMeansView(
                    idea: idea,
                    evaluationResult: result,
                    userResponse: userResponse,
                    level: level,
                    openAIService: openAIService
                )
            }
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
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
                
                // Load context-aware feedback after evaluation
                await loadContextAwareFeedback(result: result)
            } catch {
                await MainActor.run {
                    self.evaluationError = "Failed to evaluate response: \(error.localizedDescription)"
                    self.isLoadingEvaluation = false
                }
            }
        }
    }
    
    private func loadContextAwareFeedback(result: EvaluationResult) async {
        isLoadingFeedback = true
        do {
            let feedback = try await evaluationService.generateContextAwareFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: result
            )
            await MainActor.run {
                self.contextAwareFeedback = feedback
                self.isLoadingFeedback = false
            }
        } catch {
            await MainActor.run {
                self.contextAwareFeedback = "Unable to generate personalized feedback at this time."
                self.isLoadingFeedback = false
            }
        }
    }
    
    private func saveResponseAndContinue() {
        guard let result = evaluationResult else { return }
        
        isSavingResponse = true
        
        Task {
            do {
                // Save the user response with evaluation
                _ = try userResponseService.saveUserResponse(
                    ideaId: idea.id,
                    level: level,
                    prompt: prompt,
                    response: userResponse,
                    evaluation: result,
                    silverBullet: contextAwareFeedback
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
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 