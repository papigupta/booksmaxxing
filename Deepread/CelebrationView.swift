import SwiftUI
import SwiftData

struct CelebrationView: View {
    let idea: Idea
    let userResponse: String
    let level: Int
    let score: Int
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @State private var showConfetti = false
    @State private var navigateToBookOverview = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Celebration Icon
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow)
                    .scaleEffect(showConfetti ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: showConfetti)
                
                Text("🎉 Mastery Achieved! 🎉")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            
            // Achievement Details
            VStack(spacing: 16) {
                Text("You've mastered")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(idea.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("from \(idea.bookTitle)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                // Score Display
                HStack(spacing: 8) {
                    Text("Final Score:")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Text("\(score)/10")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Achievement Message
            VStack(spacing: 12) {
                Text("Congratulations!")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("You've demonstrated exceptional understanding and creative synthesis of this idea. You can now apply this knowledge to build new concepts and solve complex problems.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 16) {
                Button(action: {
                    navigateToBookOverview = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.caption)
                        Text("Master Another Idea")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue)
                    )
                }
                
                Button(action: {
                    // Share achievement
                    let shareText = "I just mastered '\(idea.title)' from '\(idea.bookTitle)' with a score of \(score)/10! 🎉"
                    let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        window.rootViewController?.present(activityVC, animated: true)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                        Text("Share Achievement")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.blue, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .padding()
        .navigationTitle("Celebration")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToBookOverview) {
            // Navigate back to book overview
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
        }
        .onAppear {
            // CRITICAL: Update mastery level to 3 when celebration appears
            print("DEBUG: Updating mastery level to 3 for idea: \(idea.title)")
            idea.masteryLevel = 3
            idea.lastPracticed = Date()
            
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
                lastPracticed: nil
            ),
            userResponse: "This is my response about Norman Doors...",
            level: 3,
            score: 9,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 