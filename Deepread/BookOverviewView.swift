import SwiftUI

struct BookOverviewView: View {
    let bookTitle: String
    @StateObject private var viewModel: IdeaExtractionViewModel

    init(bookTitle: String, openAIService: OpenAIService) {
        self.bookTitle = bookTitle
        self._viewModel = StateObject(wrappedValue: IdeaExtractionViewModel(openAIService: openAIService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(bookTitle)
                .font(.largeTitle)
                .bold()
                .tracking(-0.03)
            
            Text("Author name")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 6)
                .padding(.bottom, 32)

            if viewModel.isLoading {
                ProgressView("Breaking book into core ideas…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(viewModel.extractedIdeas.enumerated()), id: \.element.id) { index, idea in
                            if index == 0 {
                                // First idea is active (temporary - will be replaced with selection logic)
                                ActiveIdeaCard(idea: idea)
                            } else {
                                // Other ideas are inactive
                                InactiveIdeaCard(idea: idea)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            print("DEBUG: BookOverviewView task triggered")
            viewModel.extractIdeas(from: bookTitle)
        }
    }
}

// MARK: - Active Idea Card
struct ActiveIdeaCard: View {
    let idea: Idea
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "apple.intelligence")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.white)
                    
                    if !idea.description.isEmpty {
                        Text(idea.description)
                            .font(.body)
                            .fontWeight(.regular)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(3)
                    }
                    
                    // Understanding Score
                    HStack(spacing: 4) {
                        Text("Understanding score:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack(spacing: 2) {
                            ForEach(0..<3) { index in
                                Image(systemName: index < 2 ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    
                    // Important Idea
                    HStack(spacing: 4) {
                        Text("Importance:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack(spacing: 2) {
                            ForEach(0..<3) { index in
                                Image(systemName: index < idea.depthTarget ? "staroflife.fill" : "staroflife")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    
                    // CTA Button
                    NavigationLink(destination: LevelLoadingView(idea: idea)) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text("Master this idea")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.2))
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Inactive Idea Card
struct InactiveIdeaCard: View {
    let idea: Idea
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "apple.intelligence")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 16)
                .opacity(0.6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.gray)
                
                if !idea.description.isEmpty {
                    Text(idea.description)
                        .font(.body)
                        .fontWeight(.regular)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .opacity(0.6)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
