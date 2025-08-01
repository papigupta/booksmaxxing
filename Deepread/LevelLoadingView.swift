import SwiftUI

struct LevelLoadingView: View {
    let idea: Idea
    let level: Int
    let openAIService: OpenAIService
    
    @State private var showContinueButton = false
    @State private var navigateToPrompt = false
    @State private var navigateToHome = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Level Title
            Text(getLevelTitle())
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Bullet Points
            VStack(alignment: .leading, spacing: 16) {
                ForEach(getLevelBullets(), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.title2)
                            .foregroundColor(.primary)
                        
                        Text(bullet)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 32)
            
            if showContinueButton {
                Button(action: {
                    navigateToPrompt = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text("Continue")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.primary)
                .transition(.opacity)
                .opacity(showContinueButton ? 1 : 0)
                .animation(.easeIn(duration: 0.4), value: showContinueButton)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
        .navigationDestination(isPresented: $navigateToPrompt) {
            IdeaPromptView(idea: idea, level: level, openAIService: openAIService)
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
        }
        .onAppear {
            // Save current level for resume functionality
            saveCurrentLevel()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showContinueButton = true
                }
            }
        }
    }
    
    // MARK: - Progress Saving
    
    private func saveCurrentLevel() {
        idea.currentLevel = level
        idea.lastPracticed = Date()
        
        do {
            try modelContext.save()
            print("DEBUG: Saved current level \(level) for idea: \(idea.title)")
        } catch {
            print("DEBUG: Failed to save current level: \(error)")
        }
    }
    
    // MARK: - Level-specific content
    
    private func getLevelTitle() -> String {
        switch level {
        case 0:
            return "Level 0: Thought Dump"
        case 1:
            return "Level 1: Use"
        case 2:
            return "Level 2: Think With"
        case 3:
            return "Level 3: Build With"
        default:
            return "Level \(level): Advanced"
        }
    }
    
    private func getLevelBullets() -> [String] {
        switch level {
        case 0:
            return [
                "Think out loud and dump all your thoughts about \(idea.title)",
                "Messy. Personal. Half-formed. Everything works.",
                "Only write. Do not edit."
            ]
        case 1:
            return [
                "Apply \(idea.title) directly in practical situations.",
                "Find real-world examples and use cases.",
                "Focus on concrete applications and implementation."
            ]
        case 2:
            return [
                "Use \(idea.title) as a thinking tool to analyze problems.",
                "Apply this concept to understand other ideas.",
                "Explore how this idea connects to broader concepts."
            ]
        case 3:
            return [
                "Use \(idea.title) as a foundation to create new concepts.",
                "Build new systems or ideas based on this principle.",
                "Synthesize this idea with other knowledge to create something new."
            ]
        default:
            return [
                "Explore this idea deeply through structured thinking.",
                "Apply advanced analytical techniques.",
                "Create new insights and connections."
            ]
        }
    }
}

#Preview {
    NavigationStack {
        LevelLoadingView(
            idea: Idea(
                id: "i1",
                title: "Norman Doors",
                description: "Design that communicates its function through visual cues.",
                bookTitle: "The Design of Everyday Things",
                depthTarget: 2,
                masteryLevel: 0,
                lastPracticed: nil,
                currentLevel: nil
            ),
            level: 0,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 