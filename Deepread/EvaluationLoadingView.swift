import SwiftUI

struct EvaluationLoadingView: View {
    let idea: Idea
    let userResponse: String
    let level: Int
    
    @State private var currentStep = 0
    @State private var showResults = false
    
    private let loadingSteps = [
        ("Scouting for hidden insights", "🔍"),
        ("Weighing depth vs. detail", "⚖️"),
        ("Sorting you onto the mastery ladder", "🪜")
    ]
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Headline
            Text("Level scanner in progress")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Progress steps
            VStack(spacing: 16) {
                ForEach(0..<loadingSteps.count, id: \.self) { index in
                    HStack(spacing: 12) {
                        // Progress indicator
                        Circle()
                            .fill(index <= currentStep ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        
                        // Step text
                        Text("\(loadingSteps[index].0) \(loadingSteps[index].1)")
                            .font(.body)
                            .foregroundStyle(index <= currentStep ? .primary : .secondary)
                            .opacity(index <= currentStep ? 1.0 : 0.6)
                        
                        Spacer()
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResults) {
            EvaluationResultsView(
                idea: idea,
                userResponse: userResponse,
                level: level
            )
        }
        .onAppear {
            startLoadingSequence()
        }
    }
    
    private func startLoadingSequence() {
        // Simulate the evaluation process with progressive steps
        for step in 0..<loadingSteps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 1.5) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentStep = step
                }
            }
        }
        
        // Navigate to results after all steps complete
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(loadingSteps.count) * 1.5 + 1.0) {
            showResults = true
        }
    }
}

#Preview {
    NavigationStack {
        EvaluationLoadingView(
            idea: Idea(
                id: "i1",
                title: "Norman Doors",
                description: "The mind fills in blanks. But what if the blanks are the most important part?",
                bookTitle: "The Design of Everyday Things"
            ),
            userResponse: "This is my response about Norman Doors...",
            level: 0
        )
    }
} 