import SwiftUI

struct IdeaPromptView: View {
    let idea: Idea
    let level: Int
    let openAIService: OpenAIService
    
    @State private var userResponse: String = ""
    @State private var generatedPrompt: String = ""
    @State private var isLoadingPrompt: Bool = true
    @State private var showSubmitButton: Bool = false
    @State private var promptError: String? = nil
    @State private var isSubmitting: Bool = false
    @State private var navigateToEvaluation = false
    @State private var showHomeConfirmation = false
    @State private var navigateToHome = false
    @State private var showingPrimer = false // Add this line
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Computed Properties
    
    private var levelTitle: String {
        switch level {
        case 1:
            return "Level 1: Why Care"
        case 2:
            return "Level 2: When Use"
        case 3:
            return "Level 3: How Wield"
        default:
            return "Level \(level): Advanced"
        }
    }
    
    private var levelDescription: String {
        switch level {
        case 1:
            return "Explain why this idea matters and its significance in real-world contexts."
        case 2:
            return "Identify when and where to recall and apply this idea effectively."
        case 3:
            return "Wield this idea creatively or critically to extend your thinking."
        default:
            return "Advanced level requiring sophisticated understanding and application."
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content area
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Book title - subtle at top
                    Text(idea.bookTitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    // Idea title
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        // Idea title - prominent but not overwhelming
                        Text(idea.title)
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Colors.primaryText)
                    }
                    
                    // Generated prompt - MAIN FOCUS
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("Question")
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(DS.Colors.primaryText)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                            if isLoadingPrompt {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.white))
                                        .scaleEffect(0.8)
                                    Text("Generating your prompt...")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(LocalizedStringKey(generatedPrompt))
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if let error = promptError {
                                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                        Text(error)
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.white)
                                        
                                        Button("Retry") {
                                            generatePrompt()
                                        }
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.white)
                                        .underline()
                                    }
                                }
                            }
                        }
                        .padding(DS.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Colors.black)
                    }
                    
                    // Response section - SECONDARY FOCUS
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("Your Response")
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(DS.Colors.primaryText)
                        
                        TextEditor(text: $userResponse)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .frame(minHeight: 320)
                            .padding(DS.Spacing.md)
                            .background(
                                Rectangle()
                                    .fill(DS.Colors.tertiaryBackground)
                                    .overlay(
                                        Rectangle()
                                            .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
                                    )
                            )
                            .overlay(
                                Group {
                                    if userResponse.isEmpty {
                                        Text("My answer")
                                            .font(DS.Typography.body)
                                            .foregroundStyle(DS.Colors.tertiaryText)
                                            .padding(.horizontal, DS.Spacing.lg)
                                            .padding(.vertical, DS.Spacing.lg)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            .allowsHitTesting(false)
                                    }
                                }
                            )
                            .accessibilityLabel("Response text area")
                            .accessibilityHint("Type your thoughts about the idea here")
                    }
                    
                    Spacer(minLength: DS.Spacing.xl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            
            // Submit button at bottom
            if showSubmitButton {
                VStack {
                    DSDivider()
                    
                    Button(action: submitResponse) {
                        HStack(spacing: DS.Spacing.xs) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSubmitting ? "Submitting..." : "Submit answer")
                                .font(DS.Typography.captionBold)
                                .foregroundColor(DS.Colors.white)
                        }
                    }
                    .dsPrimaryButton()
                    .disabled(isSubmitting)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .accessibilityLabel("Submit your response")
                }
                .background(DS.Colors.secondaryBackground)
            }
            
            NavigationLink(value: "evaluation") {
                EmptyView()
            }
            .hidden()
            .navigationDestination(isPresented: $navigateToEvaluation) {
                EvaluationResultsView(
                    idea: idea, 
                    userResponse: userResponse, 
                    prompt: generatedPrompt,
                    level: level,
                    onOpenPrimer: {
                        showingPrimer = true
                    }
                )
            }
        }
        .navigationTitle(levelTitle)
        .navigationBarTitleDisplayMode(.inline) // Changed from .large to .inline
        .navigationBarBackButtonHidden(true) // Hide the back button
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: handleBookButtonTap) {
                    DSIcon("text.book.closed", size: 18)
                        .foregroundStyle(DS.Colors.primaryText)
                }
                .accessibilityLabel("Go to home")
                .accessibilityHint("Return to all extracted ideas")
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingPrimer = true
                }) {
                    DSIcon("lightbulb", size: 18)
                        .foregroundStyle(DS.Colors.primaryText)
                }
                .accessibilityLabel("View Primer")
                .accessibilityHint("Open primer for this idea")
            }
        }
        .onAppear {
            generatePrompt()
        }
        .onChange(of: userResponse) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                showSubmitButton = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        .alert("The response won't be saved", isPresented: $showHomeConfirmation) {
            Button("Continue") {
                navigateToHome = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to go back to home? Your current response will not be saved.")
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: openAIService)
        }
    }
    
    // MARK: - Methods
    
    private func generatePrompt() {
        isLoadingPrompt = true
        promptError = nil
        
        Task {
            do {
                let prompt = try await openAIService.generatePrompt(for: idea, level: level)
                await MainActor.run {
                    generatedPrompt = prompt
                    isLoadingPrompt = false
                }
            } catch {
                await MainActor.run {
                    promptError = "Failed to generate prompt. Please try again."
                    isLoadingPrompt = false
                    // Fallback to template
                    let fallbackPrompt = "Write everything that comes to mind when you think of \"\(idea.title)\""
                    generatedPrompt = fallbackPrompt
                }
            }
        }
    }
    
    private func submitResponse() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        isSubmitting = true
        
        // Simulate submission delay, then navigate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSubmitting = false
            navigateToEvaluation = true
        }
    }
    
    private func handleBookButtonTap() {
        // Check if there's text in the response field
        if !userResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showHomeConfirmation = true
        } else {
            // No text to save, navigate directly
            navigateToHome = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IdeaPromptView(
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
            level: 1,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
}

#Preview("Level 1") {
    NavigationStack {
        IdeaPromptView(
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
            level: 1,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 