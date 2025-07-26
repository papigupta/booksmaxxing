import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let level: Int
    let openAIService: OpenAIService
    
    @State private var evaluationResult: EvaluationResult? = nil
    @State private var isLoadingEvaluation = true
    @State private var evaluationError: String? = nil
    @State private var navigateToWhatThisMeans = false
    @State private var contextAwareFeedback: String? = nil
    @State private var isLoadingFeedback = false
    
    private var evaluationService: EvaluationService {
        EvaluationService(openAIService: openAIService)
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
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        // Idea title
                        Text(idea.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        // Score and Level
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Level")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Text(result.level)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Score")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text("\(result.score10)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                    Text("/ 10")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        // Your response
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Response")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            Text(userResponse)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        
                        // Key Insight
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Insight")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            if isLoadingFeedback {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating personalized feedback...")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            } else if let feedback = contextAwareFeedback {
                                Text(feedback)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                        
                        // Detailed Evaluation
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detailed Evaluation")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // Strengths
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(result.strengths, id: \.self) { strength in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                                .padding(.top, 2)
                                            Text(strength)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                // Improvements
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(result.improvements, id: \.self) { improvement in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "multiply.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                                .padding(.top, 2)
                                            Text(improvement)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        // Continue Button
                        Button("Continue") {
                            navigateToWhatThisMeans = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 16)
                        
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle("Evaluation Complete")
        .navigationBarTitleDisplayMode(.inline)
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
                lastPracticed: nil
            ),
            userResponse: "This is my response about Norman Doors...",
            level: 0,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 