import SwiftUI

struct IdeaPromptView: View {
    let idea: Idea
    let level: Int
    
    @State private var userResponse: String = ""
    @State private var generatedPrompt: String = ""
    @State private var isLoadingPrompt: Bool = true
    @State private var showSubmitButton: Bool = false
    @State private var promptError: String? = nil
    @State private var isSubmitting: Bool = false
    
    // Initialize OpenAI service
    private let openAIService = OpenAIService(apiKey: Secrets.openAIAPIKey)
    
    // MARK: - Computed Properties
    
    private var levelTitle: String {
        switch level {
        case 0:
            return "Level 0: Think Out Loud"
        case 1:
            return "Level 1: Connect & Reflect"
        case 2:
            return "Level 2: Apply & Synthesize"
        default:
            return "Level \(level): Deep Dive"
        }
    }
    
    private var levelDescription: String {
        switch level {
        case 0:
            return "Think out loud and dump all your thoughts about this idea. Messy. Personal. Half-formed. Everything works."
        case 1:
            return "Connect this idea to your own experiences and reflect on its implications."
        case 2:
            return "Apply this idea to new situations and synthesize it with other concepts."
        default:
            return "Explore this idea deeply through structured thinking."
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content area
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Book title - subtle at top
                    Text(idea.bookTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    // Idea title and description with 8px spacing
                    VStack(alignment: .leading, spacing: 8) {
                        // Idea title - prominent but not overwhelming
                        Text(idea.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        // Idea description - clear and readable
                        Text(idea.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Generated prompt - MAIN FOCUS
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Question")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 32) {
                            if isLoadingPrompt {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundStyle(.white)
                                    Text("Generating your prompt...")
                                        .font(.body)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(generatedPrompt)
                                    .font(.body)
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if let error = promptError {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                        
                                        Button("Retry") {
                                            generatePrompt()
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black)
                        )
                    }
                    
                    // Response section - SECONDARY FOCUS
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Response")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        TextEditor(text: $userResponse)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .frame(minHeight: 120)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.quaternary.opacity(0.3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.quaternary.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .overlay(
                                Group {
                                    if userResponse.isEmpty {
                                        Text("My answer")
                                            .font(.body)
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 20)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            .allowsHitTesting(false)
                                    }
                                }
                            )
                            .accessibilityLabel("Response text area")
                            .accessibilityHint("Type your thoughts about the idea here")
                    }
                    
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            
            // Submit button at bottom
            if showSubmitButton {
                VStack {
                    Divider()
                    
                    Button(action: submitResponse) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundStyle(.primary)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                            }
                            Text(isSubmitting ? "Submitting..." : "Submit answer")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.primary)
                    .disabled(isSubmitting)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .accessibilityLabel("Submit your response")
                }
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(levelTitle)
        .navigationBarTitleDisplayMode(.inline) // Changed from .large to .inline
        .onAppear {
            generatePrompt()
        }
        .onChange(of: userResponse) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                showSubmitButton = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
    
    // MARK: - Methods
    
    private func generatePrompt() {
        isLoadingPrompt = true
        promptError = nil
        
        Task {
            do {
                let prompt = try await openAIService.generatePrompt(for: idea.title, level: level)
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
        
        // TODO: Implement response submission
        print("Submitting response: \(userResponse)")
        
        // Simulate submission delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isSubmitting = false
            // In the future, this will save to backend and navigate to next level
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
                bookTitle: "The Design of Everyday Things"
            ),
            level: 0
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
                bookTitle: "The Design of Everyday Things"
            ),
            level: 1
        )
    }
} 