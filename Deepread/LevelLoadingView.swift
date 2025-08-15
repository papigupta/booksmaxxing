import SwiftUI

struct LevelLoadingView: View {
    let idea: Idea
    let level: Int
    let openAIService: OpenAIService
    
    @State private var showContinueButton = false
    @State private var navigateToPrompt = false
    @State private var navigateToHome = false
    @State private var showingPrimer = false // Add this line
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            
            // Level Title
            Text(getLevelTitle())
                .font(DS.Typography.title)
                .foregroundColor(DS.Colors.primaryText)
                .multilineTextAlignment(.center)
            
            // Bullet Points
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(getLevelBullets(), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: DS.Spacing.xs) {
                        Text("•")
                            .font(DS.Typography.headline)
                            .foregroundColor(DS.Colors.primaryText)
                        
                        Text(bullet)
                            .font(DS.Typography.body)
                            .foregroundColor(DS.Colors.primaryText)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            
            if showContinueButton {
                Button(action: {
                    navigateToPrompt = true
                }) {
                    Text("Continue")
                        .font(DS.Typography.captionBold)
                }
                .dsSmallButton()
                .transition(.opacity)
                .opacity(showContinueButton ? 1 : 0)
                .animation(.easeIn(duration: 0.4), value: showContinueButton)
            }
            
            Spacer()
        }
        .padding(DS.Spacing.md)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Hide the back button
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    navigateToHome = true
                }) {
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
        .navigationDestination(isPresented: $navigateToPrompt) {
            IdeaPromptView(idea: idea, level: level, openAIService: openAIService)
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: openAIService)
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
    
    private func getLevelBullets() -> [String] {
        switch level {
        case 1:
            return [
                "Explain why \(idea.title) matters in the real world.",
                "Show its importance and significance.",
                "Connect it to meaningful outcomes or impacts."
            ]
        case 2:
            return [
                "Identify when to recall and use \(idea.title).",
                "Find triggers and situations where it applies.",
                "Focus on practical recognition patterns."
            ]
        case 3:
            return [
                "Wield \(idea.title) creatively or critically to extend thinking.",
                "Find its limitations, edge cases, or creative extensions.",
                "Combine it with other ideas to generate new insights."
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
            level: 1,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 