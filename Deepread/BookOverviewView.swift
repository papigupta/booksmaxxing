import SwiftUI

struct BookOverviewView: View {
    let bookTitle: String
    let openAIService: OpenAIService
    @StateObject private var viewModel: IdeaExtractionViewModel
    @State private var activeIdeaIndex: Int = 0 // Track which idea is active
    @State private var showingDebugInfo = false
    @State private var navigateToOnboarding = false

    init(bookTitle: String, openAIService: OpenAIService, bookService: BookService) {
        self.bookTitle = bookTitle
        self.openAIService = openAIService
        self._viewModel = StateObject(wrappedValue: IdeaExtractionViewModel(openAIService: openAIService, bookService: bookService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Beautiful Header with Home Button
            headerView
            
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
        .padding(.horizontal)
        .padding(.top, 8)
        .task {
            print("DEBUG: BookOverviewView task triggered")
            await viewModel.loadOrExtractIdeas(from: bookTitle)
            // Set activeIdeaIndex to first unmastered idea after initial load
            await MainActor.run {
                if let firstUnmasteredIndex = viewModel.extractedIdeas.firstIndex(where: { $0.masteryLevel < 3 }) {
                    activeIdeaIndex = firstUnmasteredIndex
                    print("DEBUG: Set activeIdeaIndex to first unmastered idea at index \(firstUnmasteredIndex)")
                } else {
                    // If all ideas are mastered, start with the first one
                    activeIdeaIndex = 0
                    print("DEBUG: All ideas mastered, set activeIdeaIndex to 0")
                }
            }
        }
        .onAppear {
            // Only refresh if returning from other views and ideas might have changed
            // This prevents race conditions while still updating mastery levels
            if !viewModel.extractedIdeas.isEmpty {
                print("DEBUG: BookOverviewView appeared with existing ideas, checking if refresh needed")
                Task {
                    await viewModel.refreshIdeasIfNeeded()
                    // Update activeIdeaIndex if mastery levels changed
                    await MainActor.run {
                        if let firstUnmasteredIndex = viewModel.extractedIdeas.firstIndex(where: { $0.masteryLevel < 3 }) {
                            if activeIdeaIndex != firstUnmasteredIndex {
                                activeIdeaIndex = firstUnmasteredIndex
                                print("DEBUG: Updated activeIdeaIndex to \(firstUnmasteredIndex) after refresh")
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingDebugInfo) {
            DebugInfoView(bookTitle: bookTitle, viewModel: viewModel)
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToOnboarding) {
            OnboardingView(openAIService: openAIService)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top row with home button and debug
            HStack {
                // Home Button
                Button(action: {
                    navigateToOnboarding = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Select Another Book")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                #if DEBUG
                Button("Debug") {
                    showingDebugInfo = true
                }
                .font(.caption)
                .foregroundColor(.secondary)
                #endif
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
            
            // Book title and author
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.bookInfo?.title ?? bookTitle)
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .tracking(-0.03)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let author = viewModel.bookInfo?.author {
                    Text("by \(author)")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.secondary)
                } else {
                    Text("Author not specified")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
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
    @State private var showingHistory = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "apple.intelligence")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(idea.title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Show mastered badge when masteryLevel >= 3
                        if idea.masteryLevel >= 3 {
                            Text("MASTERED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(4)
                        } else if idea.masteryLevel > 0 {
                            Text("RESUME")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
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
                            ForEach(0..<min(idea.depthTarget, 5), id: \.self) { index in
                                Image(systemName: "staroflife.fill")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    
                    // CTA Buttons
                    HStack(spacing: 8) {
                        NavigationLink(destination: LevelLoadingView(idea: idea, level: getStartingLevel(), openAIService: openAIService)) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                Text(getButtonText())
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.white)
                        
                        // History button for mastered ideas
                        if idea.masteryLevel >= 3 {
                            Button(action: {
                                showingHistory = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.caption)
                                    Text("History")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.white)
                        }
                    }
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
        .sheet(isPresented: $showingHistory) {
            ResponseHistoryView(idea: idea)
        }
    }
    
    private func getButtonText() -> String {
        if idea.masteryLevel >= 3 {
            return "Remaster this idea"
        } else if idea.masteryLevel > 0 {
            return "Continue mastering"
        } else {
            return "Master this idea"
        }
    }
    
    private func getStartingLevel() -> Int {
        // If user has a saved current level, resume from there
        if let currentLevel = idea.currentLevel {
            return currentLevel
        }
        
        // Fallback to old mastery-based logic for backward compatibility
        if idea.masteryLevel >= 3 {
            // If mastered, start from beginning for remastering
            return 0
        } else if idea.masteryLevel == 2 {
            // If intermediate, start from level 3 (Build With)
            return 3
        } else if idea.masteryLevel == 1 {
            // If basic, start from level 1 (Use)
            return 1
        } else {
            // If not started, start from level 0 (Thought Dump)
            return 0
        }
    }
}

// MARK: - Inactive Idea Card
struct InactiveIdeaCard: View {
    let idea: Idea
    @Environment(\.modelContext) private var modelContext
    @State private var progressInfo: (responseCount: Int, bestScore: Int?) = (0, nil)
    
    private var userResponseService: UserResponseService {
        UserResponseService(modelContext: modelContext)
    }
    
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
                    
                    // Show appropriate badge based on progress
                    if idea.masteryLevel >= 3 {
                        Text("MASTERED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    } else if idea.masteryLevel > 0 {
                        Text("RESUME")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
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
                
                // Show progress information
                if progressInfo.responseCount > 0 {
                    HStack(spacing: 8) {
                        Text("\(progressInfo.responseCount) responses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let bestScore = progressInfo.bestScore {
                            Text("Best: \(bestScore)/10")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let lastPracticed = idea.lastPracticed {
                            Text("Last: \(formatDate(lastPracticed))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadProgressInfo()
        }
    }
    
    private func loadProgressInfo() {
        Task {
            do {
                let responses = try userResponseService.getUserResponses(for: idea.id)
                let bestScore = responses.compactMap { $0.score }.max()
                
                await MainActor.run {
                    self.progressInfo = (responses.count, bestScore)
                }
            } catch {
                print("DEBUG: Failed to load progress info: \(error)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}
