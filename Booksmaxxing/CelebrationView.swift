import SwiftUI
import SwiftData

struct CelebrationView: View {
    let idea: Idea
    let userResponse: String
    let level: Int
    let starScore: Int
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @State private var showConfetti = false
    @State private var navigateToBookOverview = false
    
    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            
            // Celebration Icon
            VStack(spacing: DS.Spacing.md) {
                DSIcon("star.circle.fill", size: 80)
                    .scaleEffect(showConfetti ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: showConfetti)
                
                Text("🎉 Mastery Achieved! 🎉")
                    .font(DS.Typography.title)
                    .foregroundColor(DS.Colors.primaryText)
                    .multilineTextAlignment(.center)
            }
            
            // Achievement Details
            VStack(spacing: DS.Spacing.md) {
                Text("You've mastered")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.secondaryText)
                
                Text(idea.title)
                    .font(DS.Typography.title)
                    .foregroundColor(DS.Colors.primaryText)
                    .multilineTextAlignment(.center)
                
                Text("from \(idea.bookTitle)")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.secondaryText)
                
                // Star Display
                HStack(spacing: DS.Spacing.xs) {
                    Text("Achievement Level:")
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Colors.secondaryText)
                    
                    HStack(spacing: 2) {
                        ForEach(1...3, id: \.self) { star in
                            DSIcon(star <= starScore ? "star.fill" : "star", size: 18)
                                .foregroundColor(star <= starScore ? DS.Colors.black : DS.Colors.tertiaryText)
                        }
                    }
                }
                .padding(.top, DS.Spacing.xs)
            }
            .dsSubtleCard(padding: DS.Spacing.lg)
            
            // Achievement Message
            VStack(spacing: DS.Spacing.sm) {
                Text("Congratulations!")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.primaryText)
                
                Text("You've demonstrated exceptional understanding and creative synthesis of this idea. You can now apply this knowledge to build new concepts and solve complex problems.")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: DS.Spacing.md) {
                Button("Master Another Idea") {
                    navigateToBookOverview = true
                }
                .dsPrimaryButton()
                
                Button("Share Achievement") {
                    // Share achievement
                    let shareText = "I just mastered '\(idea.title)' from '\(idea.bookTitle)' with \(starScore) stars! 🎉"
                    let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        window.rootViewController?.present(activityVC, animated: true)
                    }
                }
                .dsSecondaryButton()
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .padding(DS.Spacing.md)
        .navigationTitle("Celebration")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    navigateToBookOverview = true
                }) {
                    DSIcon("text.book.closed", size: 18)
                }
                .accessibilityLabel("Go to home")
                .accessibilityHint("Return to all extracted ideas")
            }
        }
        .navigationDestination(isPresented: $navigateToBookOverview) {
            // Navigate back to book overview
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
        }
        .onAppear {
            // CRITICAL: Update mastery level to 3 when celebration appears
            print("DEBUG: Updating mastery level to 3 for idea: \(idea.title)")
            idea.masteryLevel = 3
            idea.lastPracticed = Date()
            idea.currentLevel = nil // Clear current level since mastery is achieved
            
            // Save to database immediately
            do {
                try modelContext.save()
                print("DEBUG: Successfully saved mastery level update")
            } catch {
                print("DEBUG: Failed to save mastery level update: \(error)")
            }
            
            // Start confetti animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showConfetti = true
            }
            
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        }
    }
}

#Preview {
    NavigationStack {
        CelebrationView(
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
            level: 3,
            starScore: 3,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 