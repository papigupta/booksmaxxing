import SwiftUI

struct LevelLoadingView: View {
    let idea: Idea
    
    @State private var showContinueButton = false
    @State private var navigateToPrompt = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Level Title
            Text("Level 0: Thought Dump")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Bullet Points
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.title2)
                        .foregroundColor(.primary)
                    
                    Text("Think out loud and dump all your thoughts about ")
                        .font(.body)
                        .foregroundColor(.primary) +
                    Text(idea.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .italic()
                        .foregroundColor(.primary)
                }
                
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.title2)
                        .foregroundColor(.primary)
                    
                    Text("Messy. Personal. Half-formed. Everything works.")
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.title2)
                        .foregroundColor(.primary)
                    
                    Text("Only write. Do not edit.")
                        .font(.body)
                        .foregroundColor(.primary)
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
        .navigationDestination(isPresented: $navigateToPrompt) {
            IdeaPromptView(idea: idea, level: 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showContinueButton = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LevelLoadingView(idea: Idea(
            id: "i1",
            title: "Norman Doors",
            description: "Design that communicates its function through visual cues.",
            bookTitle: "The Design of Everyday Things",
            depthTarget: 2
        ))
    }
} 