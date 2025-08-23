import SwiftUI
import SwiftData

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
                DSLoadingView(message: "Breaking book into core ideas…")
                    .padding(.top, DS.Spacing.xxl)
            } else if let errorMessage = viewModel.errorMessage {
                DSErrorView(
                    title: "Network Error",
                    message: errorMessage,
                    retryAction: {
                        Task {
                            await viewModel.loadOrExtractIdeas(from: bookTitle)
                        }
                    }
                )
                .padding(.top, DS.Spacing.xxl)
            } else if viewModel.extractedIdeas.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Text("No ideas found")
                        .font(DS.Typography.headline)
                        .foregroundColor(DS.Colors.secondaryText)
                    
                    Button("Extract Ideas") {
                        Task {
                            await viewModel.loadOrExtractIdeas(from: bookTitle)
                        }
                    }
                    .dsSecondaryButton()
                    .frame(width: 200)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Spacing.xxl)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
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
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
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
                    HStack(spacing: DS.Spacing.xs) {
                        DSIcon("chevron.left", size: 14)
                        Text("Library")
                            .font(DS.Typography.captionEmphasized)
                    }
                }
                .foregroundColor(DS.Colors.secondaryText)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Colors.gray100)
                .clipShape(Capsule())
                
                Spacer()
                
                #if DEBUG
                Button("Debug") {
                    showingDebugInfo = true
                }
                .font(.caption)
                .foregroundColor(DS.Colors.tertiaryText)
                #endif
            }
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.xl)
            
            // Book cover, title and author - Enhanced design
            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                // Book Cover with enhanced shadow and styling
                ZStack {
                    // Shadow layer
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 90, height: 135)
                        .offset(x: 2, y: 3)
                        .blur(radius: 8)
                    
                    // Book Cover
                    if viewModel.currentBook?.coverImageUrl != nil || viewModel.currentBook?.thumbnailUrl != nil {
                        BookCoverView(
                            thumbnailUrl: viewModel.currentBook?.thumbnailUrl,
                            coverUrl: viewModel.currentBook?.coverImageUrl,
                            isLargeView: false
                        )
                        .frame(width: 90, height: 135)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DS.Colors.gray200, lineWidth: 0.5)
                        )
                    } else {
                        // Enhanced placeholder
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [DS.Colors.gray100, DS.Colors.gray200],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 135)
                            .overlay(
                                VStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(DS.Colors.gray400)
                                    Text("Cover")
                                        .font(DS.Typography.micro)
                                        .foregroundColor(DS.Colors.gray400)
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.Colors.gray300, lineWidth: 0.5)
                            )
                    }
                }
                
                // Book title and author with enhanced typography
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    // Title with better typography
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(viewModel.bookInfo?.title ?? bookTitle)
                            .font(DS.Typography.title2)
                            .fontWeight(.bold)
                            .tracking(-0.02)
                            .foregroundColor(DS.Colors.black)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Author with refined styling
                        if let author = viewModel.bookInfo?.author {
                            Text(author)
                                .font(DS.Typography.callout)
                                .fontWeight(.medium)
                                .foregroundColor(DS.Colors.gray600)
                                .lineLimit(1)
                        } else {
                            Text("Unknown Author")
                                .font(DS.Typography.callout)
                                .italic()
                                .foregroundColor(DS.Colors.gray400)
                        }
                    }
                    
                    // Rating section with improved visual hierarchy
                    if let rating = viewModel.currentBook?.averageRating,
                       let ratingsCount = viewModel.currentBook?.ratingsCount {
                        HStack(spacing: DS.Spacing.xs) {
                            // Star rating
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < Int(rating.rounded()) ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundColor(
                                            index < Int(rating.rounded()) ? 
                                            Color(hex: "FFB800") : DS.Colors.gray300
                                        )
                                }
                            }
                            
                            // Rating number and count
                            Text("\(String(format: "%.1f", rating))")
                                .font(DS.Typography.captionBold)
                                .foregroundColor(DS.Colors.gray700)
                            
                            Text("•")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.gray400)
                            
                            Text("\(formatRatingsCount(ratingsCount)) ratings")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.gray500)
                        }
                        .padding(.top, DS.Spacing.xxs)
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.lg)
            
            // Subtle divider
            Rectangle()
                .fill(DS.Colors.gray200)
                .frame(height: 1)
                .padding(.horizontal, -DS.Spacing.lg)
        }
        .background(DS.Colors.primaryBackground)
    }
    
    // Helper function to format ratings count
    private func formatRatingsCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
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
                            .foregroundColor(DS.Colors.secondaryText)
                        
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
                                    .foregroundColor(DS.Colors.secondaryText)
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
                        .dsSecondaryButton()
                        
                        Button("Reload from Database") {
                            Task {
                                await viewModel.loadOrExtractIdeas(from: bookTitle)
                            }
                        }
                        .dsSecondaryButton()
                        
                        #if DEBUG
                        NavigationLink("Persistence Debug") {
                            PersistenceDebugView()
                        }
                        .dsSecondaryButton()
                        
                        Button("Clear All Data") {
                            do {
                                let bookService = BookService(modelContext: modelContext)
                                try bookService.clearAllData()
                            } catch {
                                print("DEBUG: Failed to clear data: \(error)")
                            }
                        }
                        .dsSecondaryButton()
                        .foregroundColor(DS.Colors.black)
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
    @State private var showingTest = false
    @State private var currentTest: Test?
    @State private var currentIncompleteAttempt: TestAttempt?
    @State private var isGeneratingTest = false
    @State private var showingPrimer = false
    @State private var loadingMessage = "Preparing your test..."
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        Text(idea.title)
                            .font(DS.Typography.bodyBold)
                            .lineLimit(2)
                            .foregroundColor(DS.Colors.white)
                        
                        Spacer()
                        
                        // Show appropriate badge
                        if currentIncompleteAttempt != nil {
                            Text("RESUME TEST")
                                .font(DS.Typography.small)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Colors.white)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                        } else if idea.masteryLevel >= 3 {
                            Text("MASTERED")
                                .font(DS.Typography.small)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Colors.white)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(DS.Colors.black)
                                .overlay(
                                    Rectangle()
                                        .stroke(DS.Colors.white, lineWidth: DS.BorderWidth.thin)
                                )
                        } else if idea.masteryLevel > 0 {
                            Text("RESUME")
                                .font(DS.Typography.small)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Colors.black)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(DS.Colors.white)
                        }
                    }
                    
                    
                    
                    // Importance with signal bars
                    HStack(spacing: DS.Spacing.xs) {
                        let importanceLevel = idea.importance ?? .buildingBlock
                        Text(importanceLevel.rawValue)
                            .font(DS.Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(DS.Colors.white.opacity(0.9))
                        
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { index in
                                Rectangle()
                                    .fill(index < importanceLevel.barCount ? DS.Colors.white.opacity(0.9) : DS.Colors.white.opacity(0.3))
                                    .frame(width: 3, height: index == 0 ? 8 : index == 1 ? 12 : 16)
                                    .animation(.easeInOut(duration: 0.2), value: importanceLevel.barCount)
                            }
                        }
                    }
                    
                    // CTA Buttons
                    HStack(spacing: DS.Spacing.xs) {
                        // Start Test Button
                        Button(action: startTest) {
                            HStack(spacing: DS.Spacing.xs) {
                                if isGeneratingTest {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                                        .scaleEffect(0.7)
                                } else {
                                    Text(getButtonText())
                                        .font(DS.Typography.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(DS.Colors.black)
                                }
                            }
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Colors.white)
                        }
                        .disabled(isGeneratingTest)
                        
                        // Primer Button
                        Button(action: {
                            showingPrimer = true
                        }) {
                            HStack(spacing: DS.Spacing.xxs) {
                                DSIcon("lightbulb", size: 12)
                                    .foregroundStyle(DS.Colors.white)
                                Text("Primer")
                                    .font(DS.Typography.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(DS.Colors.white)
                            }
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .overlay(
                                Rectangle()
                                    .stroke(DS.Colors.white, lineWidth: DS.BorderWidth.thin)
                            )
                        }
                        
                        // History button for mastered ideas
                        if idea.masteryLevel >= 3 {
                            Button(action: {
                                showingHistory = true
                            }) {
                                HStack(spacing: DS.Spacing.xxs) {
                                    DSIcon("clock.arrow.circlepath", size: 12)
                                        .foregroundStyle(DS.Colors.white)
                                    Text("History")
                                        .font(DS.Typography.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(DS.Colors.white)
                                }
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .overlay(
                                    Rectangle()
                                        .stroke(DS.Colors.white, lineWidth: DS.BorderWidth.thin)
                                )
                            }
                        }
                    }
                .padding(.top, DS.Spacing.xxs)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.black)
        .overlay(
            Rectangle()
                .stroke(DS.Colors.white.opacity(0.2), lineWidth: DS.BorderWidth.thin)
        )
        .sheet(isPresented: $showingHistory) {
            ResponseHistoryView(idea: idea)
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: openAIService)
        }
        .fullScreenCover(isPresented: $showingTest) {
            if let test = currentTest {
                TestView(
                    idea: idea,
                    test: test,
                    openAIService: openAIService,
                    onCompletion: { attempt in
                        showingTest = false
                        currentIncompleteAttempt = nil  // Clear the incomplete attempt reference
                        // Test completed, mastery will be updated by TestResultsView
                    },
                    existingAttempt: currentIncompleteAttempt
                )
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $isGeneratingTest) {
            TestLoadingView(message: $loadingMessage)
        }
        .onAppear {
            checkForIncompleteTest()
        }
    }
    
    private func getButtonText() -> String {
        if isGeneratingTest {
            return "Preparing test..."
        } else if currentIncompleteAttempt != nil {
            return "Resume test"
        } else if idea.masteryLevel >= 3 {
            return "Take test again"
        } else if idea.masteryLevel > 0 {
            return "Continue test"
        } else {
            return "Start test"
        }
    }
    
    private func startTest() {
        // First check if there's an incomplete test attempt to resume
        checkForIncompleteTest()
        
        if currentIncompleteAttempt != nil {
            // Resume the existing test
            showingTest = true
            return
        }
        
        // Otherwise, generate a new test
        isGeneratingTest = true
        loadingMessage = "Preparing your test..."
        
        Task {
            do {
                // Update loading message progressively
                await updateLoadingMessage("Creating questions based on \(idea.title)...")
                
                let testGenerationService = TestGenerationService(
                    openAI: openAIService,
                    modelContext: modelContext
                )
                
                // Determine test type based on mastery and timing
                let testType = determineTestType()
                
                await updateLoadingMessage("Generating \(testType == "review" ? "review" : "initial") questions...")
                
                // Add slight delays between questions for better UX
                await updateLoadingMessage("Creating easy questions...")
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await updateLoadingMessage("Creating medium questions...")
                
                let test = try await testGenerationService.generateTest(
                    for: idea,
                    testType: testType
                )
                
                await updateLoadingMessage("Finalizing your test...")
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                await MainActor.run {
                    self.currentTest = test
                    self.isGeneratingTest = false
                    self.showingTest = true
                }
            } catch {
                print("Error generating test: \(error)")
                await MainActor.run {
                    self.loadingMessage = "Failed to generate test. Please try again."
                    // Delay before dismissing
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        self.isGeneratingTest = false
                    }
                }
            }
        }
    }
    
    @MainActor
    private func updateLoadingMessage(_ message: String) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.loadingMessage = message
        }
    }
    
    private func determineTestType() -> String {
        let spacedRepetitionService = SpacedRepetitionService(modelContext: modelContext)
        
        // Check if this idea needs a review test
        if spacedRepetitionService.isReviewDue(for: idea) {
            return "review"
        }
        
        return "initial"
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
            // If not started, start from level 1 (Why Care)
            return 1
        }
    }
    
    private func checkForIncompleteTest() {
        // Query for incomplete test attempts for this idea
        let ideaId = idea.id
        let descriptor = FetchDescriptor<Test>(
            predicate: #Predicate<Test> { test in
                test.ideaId == ideaId
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            let tests = try modelContext.fetch(descriptor)
            
            // Find the most recent test with an incomplete attempt
            for test in tests {
                if let lastAttempt = test.attempts.last(where: { !$0.isComplete }) {
                    currentTest = test
                    currentIncompleteAttempt = lastAttempt
                    return
                }
            }
            // No incomplete test found
            currentIncompleteAttempt = nil
        } catch {
            print("Error checking for incomplete tests: \(error)")
            currentIncompleteAttempt = nil
        }
    }
}

// MARK: - Inactive Idea Card
struct InactiveIdeaCard: View {
    let idea: Idea
    @Environment(\.modelContext) private var modelContext
    @State private var progressInfo: (responseCount: Int, bestScore: Int?) = (0, nil)
    @State private var hasIncompleteTest = false
    
    private var userResponseService: UserResponseService {
        UserResponseService(modelContext: modelContext)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(idea.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(DS.Colors.secondaryText)
                    
                    Spacer()
                    
                    // Show appropriate badge based on progress
                    if hasIncompleteTest {
                        Text("RESUME TEST")
                            .font(DS.Typography.small)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Colors.white)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                    } else if idea.masteryLevel >= 3 {
                        Text("MASTERED")
                            .font(DS.Typography.small)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Colors.white)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(DS.Colors.black)
                            .overlay(
                                Rectangle()
                                    .stroke(DS.Colors.gray300, lineWidth: DS.BorderWidth.thin)
                            )
                    } else if idea.masteryLevel > 0 {
                        Text("RESUME")
                            .font(DS.Typography.small)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Colors.black)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(DS.Colors.white)
                            .overlay(
                                Rectangle()
                                    .stroke(DS.Colors.gray300, lineWidth: DS.BorderWidth.thin)
                            )
                    }
                }
                
                
                // Show progress information
                if progressInfo.responseCount > 0 {
                    HStack(spacing: DS.Spacing.xs) {
                        Text("\(progressInfo.responseCount) responses")
                            .font(DS.Typography.small)
                            .foregroundColor(DS.Colors.tertiaryText)
                        
                        if let bestScore = progressInfo.bestScore {
                            HStack(spacing: 2) {
                                Text("Best:")
                                    .font(DS.Typography.small)
                                    .foregroundColor(DS.Colors.tertiaryText)
                                ForEach(1...3, id: \.self) { star in
                                    DSIcon(star <= bestScore ? "star.fill" : "star", size: 8)
                                        .foregroundColor(star <= bestScore ? DS.Colors.black : DS.Colors.gray300)
                                }
                            }
                        }
                        
                        if let lastPracticed = idea.lastPracticed {
                            Text("Last: \(formatDate(lastPracticed))")
                                .font(DS.Typography.small)
                                .foregroundColor(DS.Colors.tertiaryText)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.gray50)
        .overlay(
            Rectangle()
                .stroke(DS.Colors.gray300, lineWidth: DS.BorderWidth.thin)
        )
        .onAppear {
            loadProgressInfo()
            checkForIncompleteTest()
        }
    }
    
    private func loadProgressInfo() {
        Task {
            do {
                let responses = try userResponseService.getUserResponses(for: idea.id)
                let bestScore = responses.compactMap { $0.starScore }.max()
                
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
    
    private func checkForIncompleteTest() {
        // Query for incomplete test attempts for this idea
        let ideaId = idea.id
        let descriptor = FetchDescriptor<Test>(
            predicate: #Predicate<Test> { test in
                test.ideaId == ideaId
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            let tests = try modelContext.fetch(descriptor)
            
            // Check if there's any incomplete attempt
            for test in tests {
                if test.attempts.contains(where: { !$0.isComplete }) {
                    hasIncompleteTest = true
                    return
                }
            }
            hasIncompleteTest = false
        } catch {
            print("Error checking for incomplete tests: \(error)")
            hasIncompleteTest = false
        }
    }
}
