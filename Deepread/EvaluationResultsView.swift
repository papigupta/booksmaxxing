import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let level: Int
    
    @State private var evaluation: String = "Great effort! Your response shows thoughtful engagement with the concept. Keep exploring and connecting ideas in your own unique way."
    @State private var isLoadingEvaluation = false
    @State private var evaluationError: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    
                    // Your response section (read-only) - now on top
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
                    
                    // Evaluation section - now below
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Evaluation")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 32) {
                            Text(evaluation)
                                .font(.body)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black)
                        )
                    }
                    
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Evaluation Complete")
        .navigationBarTitleDisplayMode(.inline)
    }
    
}

#Preview {
    NavigationStack {
        EvaluationResultsView(
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