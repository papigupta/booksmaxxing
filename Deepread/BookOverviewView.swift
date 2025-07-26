import SwiftUI

struct BookOverviewView: View {
    let bookTitle: String
    let openAIService: OpenAIService
    @StateObject private var viewModel: IdeaExtractionViewModel
    @State private var activeIdeaIndex: Int = 0 // Track which idea is active
    @State private var showingDebugInfo = false

    init(bookTitle: String, openAIService: OpenAIService, bookService: BookService) {
        self.bookTitle = bookTitle
        self.openAIService = openAIService
        self._viewModel = StateObject(wrappedValue: IdeaExtractionViewModel(openAIService: openAIService, bookService: bookService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(viewModel.bookInfo?.title ?? bookTitle)
                    .font(.largeTitle)
                    .bold()
                    .tracking(-0.03)
                
                Spacer()
                
                #if DEBUG
                Button("Debug") {
                    showingDebugInfo = true
                }
                .font(.caption)
                .foregroundColor(.secondary)
                #endif
            }
            
            if let author = viewModel.bookInfo?.author {
                Text(author)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
            } else {
                Text("Author not specified")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
            }

            if viewModel.isLoading {
                ProgressView("Breaking book into core ideas…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Text("⚠️ Network Error")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        Task {
                            await viewModel.loadOrExtractIdeas(from: bookTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
            } else if viewModel.extractedIdeas.isEmpty {
                VStack(spacing: 16) {
                    Text("No ideas found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button("Extract Ideas") {
                        Task {
                            await viewModel.loadOrExtractIdeas(from: bookTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(viewModel.extractedIdeas.enumerated()), id: \.element.id) { index, idea in
                            if index == activeIdeaIndex {
                                ActiveIdeaCard(idea: idea, openAIService: openAIService)
                            } else {
                                InactiveIdeaCard(idea: idea)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            activeIdeaIndex = index
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            print("DEBUG: BookOverviewView task triggered")
            await viewModel.loadOrExtractIdeas(from: bookTitle)
            // Set activeIdeaIndex to first unmastered idea after initial load
            await MainActor.run {
                if let firstUnmasteredIndex = viewModel.extractedIdeas.firstIndex(where: { $0.masteryLevel < 3 }) {
                    activeIdeaIndex = firstUnmasteredIndex
                    print("DEBUG: Set activeIdeaIndex to first unmastered idea at index \(firstUnmasteredIndex)")
                }
            }
        }
        .onAppear {
            print("DEBUG: BookOverviewView appeared")
            // Refresh ideas when view appears (e.g., returning from other views)
            Task {
                await viewModel.refreshIdeas()
                // Set activeIdeaIndex to first unmastered idea
                await MainActor.run {
                    if let firstUnmasteredIndex = viewModel.extractedIdeas.firstIndex(where: { $0.masteryLevel < 3 }) {
                        activeIdeaIndex = firstUnmasteredIndex
                        print("DEBUG: Set activeIdeaIndex to first unmastered idea at index \(firstUnmasteredIndex)")
                    }
                }
            }
        }
        .sheet(isPresented: $showingDebugInfo) {
            DebugInfoView(bookTitle: bookTitle, viewModel: viewModel)
        }
    }
}

// MARK: - Debug Info View
struct DebugInfoView: View {
    let bookTitle: String
    let viewModel: IdeaExtractionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Information")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Book Title: '\(viewModel.bookInfo?.title ?? bookTitle)'")
                            .font(.body)
                        
                        Text("Original Input: '\(bookTitle)'")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if let author = viewModel.bookInfo?.author {
                            Text("Author: '\(author)'")
                                .font(.body)
                        }
                        
                        Text("Loading State: \(viewModel.isLoading ? "Yes" : "No")")
                            .font(.body)
                        
                        Text("Error Message: \(viewModel.errorMessage ?? "None")")
                            .font(.body)
                        
                        Text("Extracted Ideas Count: \(viewModel.extractedIdeas.count)")
                            .font(.body)
                        
                        if !viewModel.extractedIdeas.isEmpty {
                            Text("Idea IDs:")
                                .font(.body)
                                .fontWeight(.semibold)
                            
                            ForEach(viewModel.extractedIdeas, id: \.id) { idea in
                                Text("• \(idea.id): \(idea.title)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                    
                    VStack(spacing: 12) {
                        Text("Debug Actions")
                            .font(.headline)
                        
                        Button("Refresh Ideas") {
                            Task {
                                await viewModel.refreshIdeas()
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Reload from Database") {
                            Task {
                                await viewModel.loadOrExtractIdeas(from: bookTitle)
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        #if DEBUG
                        Button("Clear All Data") {
                            do {
                                let bookService = BookService(modelContext: modelContext)
                                try bookService.clearAllData()
                            } catch {
                                print("DEBUG: Failed to clear data: \(error)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        #endif
                    }
                }
                .padding()
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Active Idea Card
struct ActiveIdeaCard: View {
    let idea: Idea
    let openAIService: OpenAIService
    
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
                    
                    if !idea.ideaDescription.isEmpty {
                        Text(idea.ideaDescription)
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
                    NavigationLink(destination: LevelLoadingView(idea: idea, level: 0, openAIService: openAIService)) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            Text("Master this idea")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.white)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack {
                    Text(idea.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    // CRITICAL: Show mastered badge when masteryLevel >= 3
                    if idea.masteryLevel >= 3 {
                        Text("MASTERED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                if !idea.ideaDescription.isEmpty {
                    Text(idea.ideaDescription)
                        .font(.body)
                        .fontWeight(.regular)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .opacity(0.6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
