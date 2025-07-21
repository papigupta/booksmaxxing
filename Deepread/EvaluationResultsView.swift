import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let level: Int
    
    @State private var evaluationResult: EvaluationResult? = nil
    @State private var isLoadingEvaluation = true
    @State private var evaluationError: String? = nil
    @State private var navigateToWhatThisMeans = false
    
    private let evaluationService = EvaluationService(openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey))
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoadingEvaluation {
                VStack(spacing: 32) {
                    Spacer()
                    
                    // Headline
                    Text("Level scanner in progress")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    // Progress steps
                    VStack(spacing: 16) {
                        let loadingSteps = [
                            ("Scouting for hidden insights", "🔍"),
                            ("Weighing depth vs. detail", "⚖️"),
                            ("Sorting you onto the mastery ladder", "🪜")
                        ]
                        
                        ForEach(0..<loadingSteps.count, id: \.self) { index in
                            HStack(spacing: 12) {
                                // Progress indicator
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 8, height: 8)
                                
                                // Step text
                                Text("\(loadingSteps[index].0) \(loadingSteps[index].1)")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Footer helper text
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
                        // Book title - subtle at top
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
                        
                        // Score and Level Section
                        VStack(alignment: .leading, spacing: 12) {
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
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.quaternary.opacity(0.3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.quaternary.opacity(0.5), lineWidth: 1)
                                    )
                            )
                        }
                        

                        
                        // Your response section (read-only)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Response")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(userResponse)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.quaternary.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.quaternary.opacity(0.5), lineWidth: 1)
                                        )
                                )
                        }
                        
                        // Strengths section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Strengths")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
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
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.green.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.green.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Improvements section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Areas for Improvement")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(result.improvements, id: \.self) { improvement in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                            .padding(.top, 2)
                                        Text(improvement)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Continue Button
                        Button(action: {
                            navigateToWhatThisMeans = true
                        }) {
                            HStack {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.blue)
                            )
                        }
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
                    level: level
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
            } catch {
                await MainActor.run {
                    self.evaluationError = "Failed to evaluate response: \(error.localizedDescription)"
                    self.isLoadingEvaluation = false
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
                depthTarget: 2
            ),
            userResponse: "This is my response about Norman Doors...",
            level: 0
        )
    }
} 