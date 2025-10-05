import SwiftUI
import SwiftData

@MainActor
struct BookOverviewView: View {
    let bookTitle: String
    let openAIService: OpenAIService
    @StateObject private var viewModel: IdeaExtractionViewModel
    @State private var showingDebugInfo = false
    @State private var navigateToOnboarding = false
    @State private var showingDailyPractice = false
    @State private var showingProfile = false
    @State private var didPrefetchLesson1 = false
    @State private var showingDeleteAlert = false
    @State private var showDeletionToast = false
    @EnvironmentObject var navigationState: NavigationState
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    init(bookTitle: String, openAIService: OpenAIService, bookService: BookService) {
        self.bookTitle = bookTitle
        self.openAIService = openAIService
        self._viewModel = StateObject(wrappedValue: IdeaExtractionViewModel(openAIService: openAIService, bookService: bookService))
    }

    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(alignment: .leading, spacing: 0) {
            // Beautiful Header with Home Button
            headerView
            
            if viewModel.isLoading {
                DSLoadingView(message: "Breaking book into core ideas…")
                    .padding(.top, DS.Spacing.xxl)
                Spacer()
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
                Spacer()
            } else if viewModel.extractedIdeas.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                        Text("No ideas found")
                            .font(DS.Typography.headline)
                            .foregroundColor(theme.onSurface.opacity(0.7))
                    
                    Button("Extract Ideas") {
                        Task {
                            await viewModel.loadOrExtractIdeas(from: bookTitle)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.lg)
                    .background(theme.primary)
                    .foregroundColor(theme.onPrimary)
                    .cornerRadius(6)
                    .frame(width: 200)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Spacing.xxl)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(viewModel.extractedIdeas, id: \.id) { idea in
                            NavigationLink {
                                IdeaResponsesView(idea: idea)
                            } label: {
                                UnifiedIdeaListItem(idea: idea)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, DS.Spacing.xs)
                }
                
                // Fixed Footer Button
                if !viewModel.extractedIdeas.isEmpty {
                    Button(action: {
                        print("DEBUG: Start Practicing button tapped")
                        showingDailyPractice = true
                    }) {
                        Text("Start Practicing")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(theme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.lg)
                            .background(theme.primary)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
        .background(theme.background)
        .overlay(alignment: .bottom) {
            if showDeletionToast {
                let t = themeManager.currentTokens(for: colorScheme)
                Text("Book deleted")
                    .font(DS.Typography.caption)
                    .foregroundColor(t.onPrimary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(t.primary)
                    .cornerRadius(16)
                    .shadow(radius: 3)
                    .padding(.bottom, DS.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            withAnimation { showDeletionToast = false }
                        }
                    }
            }
        }
        .task {
            print("DEBUG: BookOverviewView task triggered")
            await viewModel.loadOrExtractIdeas(from: bookTitle)
            await MainActor.run {
                print("DEBUG: extractedIdeas count: \(viewModel.extractedIdeas.count)")
                print("DEBUG: FAB should be visible: \(!viewModel.extractedIdeas.isEmpty)")
            }
            // If ideas already loaded here, fire prefetch once
            if !viewModel.extractedIdeas.isEmpty, !didPrefetchLesson1, let book = viewModel.currentBook {
                didPrefetchLesson1 = true
                let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
                prefetcher.prefetchLesson(book: book, lessonNumber: 1)
                print("DEBUG: Prefetch for Lesson 1 triggered from BookOverviewView.task")
            }
        }
        .onAppear {
            print("DEBUG: BookOverviewView appeared")
            // Activate theme for current book
            if let book = viewModel.currentBook {
                Task { await themeManager.activateTheme(for: book) }
            }
            // Only refresh if returning from other views and ideas might have changed
            // This prevents race conditions while still updating mastery levels
            if !viewModel.extractedIdeas.isEmpty {
                print("DEBUG: BookOverviewView appeared with existing ideas, refreshing mastery data")
                Task {
                    await viewModel.refreshIdeasIfNeeded()
                }
            }
        }
        .onChange(of: viewModel.extractedIdeas.count) { _, newCount in
            // As soon as ideas are available, prefetch Lesson 1 once
            guard newCount > 0, didPrefetchLesson1 == false else { return }
            if let book = viewModel.currentBook {
                didPrefetchLesson1 = true
                let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
                prefetcher.prefetchLesson(book: book, lessonNumber: 1)
                print("DEBUG: Prefetch for Lesson 1 triggered from BookOverviewView (ideas count change)")
            } else {
                print("DEBUG: Ideas loaded but currentBook nil; will prefetch when currentBook is set")
            }
        }
        .onChange(of: viewModel.currentBook?.id) { _, _ in
            // If currentBook becomes available after ideas, fire prefetch
            guard !didPrefetchLesson1, let book = viewModel.currentBook, !viewModel.extractedIdeas.isEmpty else { return }
            Task { await themeManager.activateTheme(for: book) }
            didPrefetchLesson1 = true
            let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
            prefetcher.prefetchLesson(book: book, lessonNumber: 1)
            print("DEBUG: Prefetch for Lesson 1 triggered from BookOverviewView (currentBook change)")
        }
        .sheet(isPresented: $showingDebugInfo) {
            DebugInfoView(bookTitle: bookTitle, viewModel: viewModel)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView(authManager: authManager)
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToOnboarding) {
            OnboardingView(openAIService: openAIService)
        }
        .fullScreenCover(isPresented: $showingDailyPractice) {
            if let book = viewModel.currentBook {
                DailyPracticeHomepage(book: book, openAIService: openAIService)
            }
        }
        .alert("Delete \"\(viewModel.bookInfo?.title ?? bookTitle)\"?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task { await deleteCurrentBook() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all data and progress for this book, including generated questions, practice sessions, coverage, review queue, primers, and your answers. This action cannot be undone.")
        }
    }

    private func deleteCurrentBook() async {
        guard let book = viewModel.currentBook ?? (try? BookService(modelContext: modelContext).getBook(withTitle: bookTitle)) ?? nil else {
            return
        }
        do {
            let service = BookService(modelContext: modelContext)
            // Proactively detach UI state to avoid holding references during deletion
            await MainActor.run {
                viewModel.extractedIdeas = []
                viewModel.currentBook = nil
            }
            try service.deleteBookAndAllData(book: book)
            showingDailyPractice = false
            showingProfile = false
            await MainActor.run {
                withAnimation { showDeletionToast = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                navigationState.navigateToBookSelection()
            }
        } catch {
            print("ERROR: Failed to delete book: \(error)")
        }
    }

    // MARK: - Book Coverage View
    private func getBookId() -> String {
        // Ensure we use the actual book UUID, not the title
        if let book = viewModel.currentBook {
            return book.id.uuidString
        } else {
            // Fallback: try to find the book by title
            let bookService = BookService(modelContext: modelContext)
            if let book = try? bookService.getBook(withTitle: bookTitle) {
                return book.id.uuidString
            } else {
                print("WARNING: Could not find book, using title as bookId")
                return bookTitle // Last resort, won't match
            }
        }
    }
    
    @ViewBuilder
    private var bookCoverageView: some View {
        let bookId = getBookId()
        let coverageService = CoverageService(modelContext: modelContext)
        let bookCoverage = coverageService.calculateBookCoverage(bookId: bookId, totalIdeas: viewModel.extractedIdeas.count)
        let _ = print("DEBUG: Book coverage for bookId '\(bookId)': \(bookCoverage)%")
        
        VStack(spacing: DS.Spacing.xs) {
            HStack {
                Text("Book Coverage")
                    .font(DS.Typography.caption)
                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                Spacer()
                Text("\(Int(bookCoverage))%")
                    .font(DS.Typography.bodyBold)
                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface)
            }
            
            ProgressView(value: bookCoverage / 100)
                .progressViewStyle(LinearProgressViewStyle(tint: themeManager.currentTokens(for: colorScheme).primary))
                .frame(height: 6)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(themeManager.currentTokens(for: colorScheme).surfaceVariant)
        .cornerRadius(8)
        .padding(.bottom, DS.Spacing.sm)
    }
    
    private func bookCoverageColor(_ coverage: Double) -> Color {
        switch coverage {
        case 0..<25:
            return DS.Colors.gray400
        case 25..<50:
            return DS.Colors.gray500
        case 50..<75:
            return DS.Colors.gray700
        case 75..<100:
            return DS.Colors.gray900
        case 100:
            return Color.green
        default:
            return DS.Colors.gray300
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top row with home button, streak, and overflow menu
            HStack {
                // Home Button
                Button(action: {
                    // Use NavigationState to navigate back to book selection
                    navigationState.navigateToBookSelection()
                }) {
                    HStack(spacing: DS.Spacing.xs) {
                        DSIcon("house.fill", size: 16)
                        Text("Select Another Book")
                            .font(DS.Typography.caption)
                    }
                }
                .dsSmallButton()
                
                Spacer()

                // Streak indicator
                StreakIndicatorView()

                // Overflow menu with Review Practice and Debug actions
                Menu {
                    if let book = viewModel.currentBook {
                        let bookId = book.id.uuidString
                        let rq = ReviewQueueManager(modelContext: modelContext)
                        let stats = rq.getQueueStatistics(bookId: bookId)
                        let count = stats.totalMCQs + stats.totalOpenEnded
                        if count > 0 {
                            Button(action: {
                                // Open Daily Practice, user can jump to review from there
                                showingDailyPractice = true
                            }) {
                                Label("Review Practice (\(count))", systemImage: "clock.arrow.circlepath")
                            }
                        }
                        if DebugFlags.enableDevControls {
                            Button(action: {
                                CloudSyncRefresh(modelContext: modelContext).warmFetches()
                            }) {
                                Label("Refresh from Cloud", systemImage: "arrow.clockwise")
                            }
                            Button(action: {
                                let service = CurveballService(modelContext: modelContext)
                                service.forceAllCurveballsDue(bookId: bookId, bookTitle: book.title)
                            }) {
                                Label("Force Curveball Due", systemImage: "bolt.fill")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete this book", systemImage: "trash")
                        }
                    }
                    Button("Profile") { showingProfile = true }
                    Button("Debug Info") { showingDebugInfo = true }
                    Divider()
                    Button(role: .destructive) {
                        authManager.signOut()
                        // Toggle app back to auth screen immediately
                        navigationState.shouldShowBookSelection = false
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface)
                        .padding(.leading, DS.Spacing.sm)
                }
                .contentShape(Rectangle())
            }
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.md)
            
            // Book cover, title and author
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // Book Cover
                if viewModel.currentBook?.coverImageUrl != nil || viewModel.currentBook?.thumbnailUrl != nil {
                    BookCoverView(
                        thumbnailUrl: viewModel.currentBook?.thumbnailUrl,
                        coverUrl: viewModel.currentBook?.coverImageUrl,
                        isLargeView: false
                    )
                    .frame(width: 80, height: 120)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                }
                
                // Book title and author
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(viewModel.bookInfo?.title ?? bookTitle)
                        .font(DS.Typography.largeTitle)
                        .tracking(-0.03)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface)
                        .lineLimit(2)
                    
                    if let author = viewModel.bookInfo?.author {
                        Text("by \(author)")
                            .font(DS.Typography.body)
                            .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                    } else {
                        Text("Author not specified")
                            .font(DS.Typography.body)
                            .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.6))
                    }
                    
                    // Show rating if available
                    if let rating = viewModel.currentBook?.averageRating,
                       let ratingsCount = viewModel.currentBook?.ratingsCount {
                        HStack(spacing: DS.Spacing.xxs) {
                            ForEach(0..<5) { index in
                                Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                            }
                            Text("(\(ratingsCount))")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.tertiaryText)
                        }
                        .padding(.top, DS.Spacing.xxs)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, DS.Spacing.sm)
            
            // Book Coverage Display (full-width)
            if !viewModel.extractedIdeas.isEmpty {
                bookCoverageView
            }
        }
        .background(themeManager.currentTokens(for: colorScheme).surface)
    }
}

// MARK: - Unified Idea List Item
struct UnifiedIdeaListItem: View {
    let idea: Idea
    @Environment(\.modelContext) private var modelContext
    @State private var ideaCoverage: IdeaCoverage?
    
    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            // Left: Idea Title
            VStack(alignment: .leading, spacing: 2) {
                Text(idea.title)
                    .font(DS.Typography.caption)
                    .fontWeight(.light)
                    .lineLimit(2)
                    .foregroundColor(DS.Colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Center: Coverage Percentage / Mastery
            VStack(alignment: .center, spacing: 4) {
                if let coverage = ideaCoverage, coverage.coveragePercentage > 0 {
                    Text(coverage.curveballPassed ? "Mastered" : "\(Int(coverage.coveragePercentage))%")
                        .font(DS.Typography.caption)
                        .fontWeight(.light)
                        .foregroundColor(DS.Colors.primaryText)
                    
                    ProgressView(value: coverage.coveragePercentage / 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: coverageColor))
                        .frame(width: 60, height: 3)
                } else {
                    Text("0%")
                        .font(DS.Typography.caption)
                        .fontWeight(.light)
                        .foregroundColor(DS.Colors.tertiaryText)
                    
                    ProgressView(value: 0)
                        .progressViewStyle(LinearProgressViewStyle(tint: DS.Colors.gray300))
                        .frame(width: 60, height: 3)
                }
            }
            .frame(width: 80)
            
            // Right: Importance Level
            VStack(alignment: .trailing, spacing: 4) {
                let importanceLevel = idea.importance ?? .buildingBlock
                Text(importanceLevel.rawValue)
                    .font(DS.Typography.caption)
                    .fontWeight(.light)
                    .foregroundColor(DS.Colors.secondaryText)
                
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(index < importanceLevel.barCount ? DS.Colors.primaryText : DS.Colors.gray300)
                            .frame(width: 3, height: index == 0 ? 6 : index == 1 ? 10 : 14)
                    }
                }
            }
            .frame(width: 100, alignment: .trailing)
        }
        // Remove horizontal padding to feel like a simple list
        .padding(.vertical, DS.Spacing.md)
        // Bottom divider only
        .overlay(
            Rectangle()
                .frame(height: DS.BorderWidth.thin)
                .foregroundColor(DS.Colors.subtleBorder),
            alignment: .bottom
        )
        .onAppear {
            loadCoverageData()
        }
    }
    
    private var coverageColor: Color {
        guard let coverage = ideaCoverage else { return DS.Colors.gray300 }
        
        switch coverage.coveragePercentage {
        case 0..<30:
            return DS.Colors.gray400
        case 30..<70:
            return DS.Colors.gray600
        case 70..<100:
            return DS.Colors.gray800
        case 100:
            return DS.Colors.black
        default:
            return DS.Colors.gray300
        }
    }
    
    private func loadCoverageData() {
        // Get the book ID from the viewModel's currentBook if available
        // This ensures consistency with how coverage is saved
        let bookId: String
        if let book = idea.book {
            bookId = book.id.uuidString
        } else {
            // Fallback: try to find the book by title
            let bookService = BookService(modelContext: modelContext)
            if let book = try? bookService.getBook(withTitle: idea.bookTitle) {
                bookId = book.id.uuidString
            } else {
                // Last resort: use the book title (this won't match saved coverage)
                bookId = idea.bookTitle
                print("WARNING: Could not find book for idea '\(idea.id)', using title as bookId")
            }
        }
        
        print("DEBUG: Loading coverage for idea '\(idea.id)' with bookId: '\(bookId)'")
        print("DEBUG: Idea has book relationship: \(idea.book != nil)")
        let coverageService = CoverageService(modelContext: modelContext)
        ideaCoverage = coverageService.getCoverage(for: idea.id, bookId: bookId)
        print("DEBUG: Loaded coverage: \(ideaCoverage?.coveragePercentage ?? 0)%, categories: \(ideaCoverage?.coveredCategories.count ?? 0)")
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
    @State private var showingTest = false
    @State private var currentTest: Test?
    @State private var currentIncompleteAttempt: TestAttempt?
    @State private var isGeneratingTest = false
    @State private var showingPrimer = false
    @State private var loadingMessage = "Preparing your test..."
    @State private var ideaCoverage: IdeaCoverage?
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.title)
                                .font(DS.Typography.bodyBold)
                                .lineLimit(2)
                                .foregroundColor(DS.Colors.white)
                            
                            // Coverage progress bar
                            if let coverage = ideaCoverage {
                                HStack(spacing: DS.Spacing.xxs) {
                                    ProgressView(value: coverage.coveragePercentage / 100)
                                        .progressViewStyle(LinearProgressViewStyle(tint: coverageColor))
                                        .frame(width: 100, height: 4)
                                    
                                    Text(coverage.curveballPassed ? "Mastered" : "\(Int(coverage.coveragePercentage))%")
                                        .font(DS.Typography.small)
                                        .foregroundColor(DS.Colors.white.opacity(0.8))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Show appropriate badge
                        if let coverage = ideaCoverage, coverage.curveballPassed {
                            // Golden mastered state
                            VStack(spacing: 2) {
                                Text("MASTERED")
                                    .font(DS.Typography.small)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.black)
                                    .padding(.horizontal, DS.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow)
                                if let passedAt = coverage.curveballPassedAt {
                                    Text("Since \(formatDate(passedAt))")
                                        .font(DS.Typography.caption)
                                        .foregroundColor(DS.Colors.white.opacity(0.9))
                                }
                            }
                        } else if let coverage = ideaCoverage, coverage.isFullyCovered {
                            VStack(spacing: 2) {
                                Text("COVERED")
                                    .font(DS.Typography.small)
                                    .fontWeight(.bold)
                                    .foregroundColor(DS.Colors.white)
                                    .padding(.horizontal, DS.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                
                                if let reviewData = coverage.reviewStateData,
                                   let reviewState = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewData) {
                                    let daysUntilReview = Calendar.current.dateComponents([.day], from: Date(), to: reviewState.nextReviewDate).day ?? 0
                                    if daysUntilReview <= 0 {
                                        Text("Review due")
                                            .font(DS.Typography.caption)
                                            .foregroundColor(DS.Colors.white.opacity(0.8))
                                    } else {
                                        Text("Review in \(daysUntilReview)d")
                                            .font(DS.Typography.caption)
                                            .foregroundColor(DS.Colors.white.opacity(0.8))
                                    }
                                }
                            }
                        } else if currentIncompleteAttempt != nil {
                            Text("RESUME TEST")
                                .font(DS.Typography.small)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Colors.white)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                        } else if let coverage = ideaCoverage, coverage.coveragePercentage > 0 {
                            Text("IN PROGRESS")
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
                    
                    // CTA Buttons - Hidden per user request
                    // HStack(spacing: DS.Spacing.xs) {
                    //     // Start Test Button
                    //     Button(action: startTest) {
                    //         HStack(spacing: DS.Spacing.xs) {
                    //             if isGeneratingTest {
                    //                 ProgressView()
                    //                     .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                    //                     .scaleEffect(0.7)
                    //             } else {
                    //                 Text(getButtonText())
                    //                     .font(DS.Typography.caption)
                    //                     .fontWeight(.medium)
                    //                     .foregroundColor(DS.Colors.black)
                    //             }
                    //         }
                    //         .padding(.horizontal, DS.Spacing.sm)
                    //         .padding(.vertical, DS.Spacing.xs)
                    //         .background(DS.Colors.white)
                    //     }
                    //     .disabled(isGeneratingTest)
                    //     
                    //     // Primer Button
                    //     Button(action: {
                    //         showingPrimer = true
                    //     }) {
                    //         HStack(spacing: DS.Spacing.xxs) {
                    //             DSIcon("lightbulb", size: 12)
                    //                 .foregroundStyle(DS.Colors.white)
                    //             Text("Primer")
                    //                 .font(DS.Typography.caption)
                    //                 .fontWeight(.medium)
                    //                 .foregroundColor(DS.Colors.white)
                    //         }
                    //         .padding(.horizontal, DS.Spacing.sm)
                    //         .padding(.vertical, DS.Spacing.xs)
                    //         .overlay(
                    //             Rectangle()
                    //                 .stroke(DS.Colors.white, lineWidth: DS.BorderWidth.thin)
                    //         )
                    //     }
                    //     
                    // }
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
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: openAIService)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showingTest) {
            if let test = currentTest {
                TestView(
                    idea: idea,
                    test: test,
                    openAIService: openAIService,
                    onCompletion: { attempt, _ in
                        showingTest = false
                        currentIncompleteAttempt = nil  // Clear the incomplete attempt reference
                        // Test completed, mastery will be updated by TestResultsView
                    },
                    onExit: { showingTest = false },
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
            loadCoverageData()
            
            // Set up periodic refresh timer for active card
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                loadCoverageData()
            }
        }
    }
    
    private var coverageColor: Color {
        guard let coverage = ideaCoverage else { return Color.gray }
        
        // Special golden theme for mastered
        if coverage.curveballPassed {
            return Color.yellow
        }

        switch coverage.coveragePercentage {
        case 0..<30:
            return Color.red
        case 30..<70:
            return Color.orange
        case 70..<100:
            return Color.yellow
        case 100:
            return coverage.curveballPassed ? Color.yellow : Color.green
        default:
            return Color.gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
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
                let attempts = test.attempts ?? []
                if let lastAttempt = attempts.last(where: { !$0.isComplete }) {
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
    
    private func loadCoverageData() {
        // Get the proper book ID
        let bookId: String
        if let book = idea.book {
            bookId = book.id.uuidString
        } else {
            // Fallback: try to find the book by title
            let bookService = BookService(modelContext: modelContext)
            if let book = try? bookService.getBook(withTitle: idea.bookTitle) {
                bookId = book.id.uuidString
            } else {
                bookId = idea.bookTitle
                print("WARNING: Could not find book for idea '\(idea.id)', using title as bookId")
            }
        }
        
        let coverageService = CoverageService(modelContext: modelContext)
        let newCoverage = coverageService.getCoverage(for: idea.id, bookId: bookId)
        
        // Only update if there's a meaningful change
        let oldPercentage = ideaCoverage?.coveragePercentage ?? 0
        let newPercentage = newCoverage.coveragePercentage
        
        ideaCoverage = newCoverage
        
        if abs(oldPercentage - newPercentage) > 0.1 {
            print("DEBUG: Coverage updated for idea \(idea.id): \(oldPercentage)% -> \(newPercentage)%")
        }
    }
}

// MARK: - Inactive Idea Card
struct InactiveIdeaCard: View {
    let idea: Idea
    @Environment(\.modelContext) private var modelContext
    @State private var progressInfo: (responseCount: Int, bestScore: Int?) = (0, nil)
    @State private var hasIncompleteTest = false
    @State private var ideaCoverage: IdeaCoverage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(idea.title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .foregroundColor(DS.Colors.secondaryText)
                        
                        // Coverage progress for inactive cards
                        if let coverage = ideaCoverage, coverage.curveballPassed {
                            HStack(spacing: DS.Spacing.xxs) {
                                Text("MASTERED")
                                    .font(DS.Typography.small)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.black)
                                    .padding(.horizontal, DS.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow)
                            }
                        } else if let coverage = ideaCoverage, coverage.coveragePercentage > 0 {
                            HStack(spacing: DS.Spacing.xxs) {
                                ProgressView(value: coverage.coveragePercentage / 100)
                                    .progressViewStyle(LinearProgressViewStyle(tint: inactiveCoverageColor))
                                    .frame(width: 80, height: 3)
                                
                                Text(coverage.curveballPassed ? "Mastered" : "\(Int(coverage.coveragePercentage))%")
                                    .font(DS.Typography.caption)
                                    .foregroundColor(DS.Colors.tertiaryText)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Show appropriate badge based on coverage
                    if let coverage = ideaCoverage, coverage.isFullyCovered {
                        Text("COVERED")
                            .font(DS.Typography.small)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Colors.white)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .overlay(
                                Rectangle()
                                    .stroke(DS.Colors.gray300, lineWidth: DS.BorderWidth.thin)
                            )
                    } else if hasIncompleteTest {
                        Text("RESUME TEST")
                            .font(DS.Typography.small)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Colors.white)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                    } else if let coverage = ideaCoverage, coverage.coveragePercentage > 0 {
                        Text("IN PROGRESS")
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
            checkForIncompleteTest()
            loadCoverageData()
        }
    }
    
    private var inactiveCoverageColor: Color {
        guard let coverage = ideaCoverage else { return DS.Colors.gray300 }

        if coverage.curveballPassed {
            return Color.yellow
        }

        switch coverage.coveragePercentage {
        case 0..<30:
            return DS.Colors.gray500
        case 30..<70:
            return DS.Colors.gray600
        case 70..<100:
            return DS.Colors.gray700
        case 100:
            return Color.green
        default:
            return DS.Colors.gray300
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
                let attempts = test.attempts ?? []
                if attempts.contains(where: { !$0.isComplete }) {
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
    
    private func loadCoverageData() {
        // Get the proper book ID
        let bookId: String
        if let book = idea.book {
            bookId = book.id.uuidString
        } else {
            // Fallback: try to find the book by title
            let bookService = BookService(modelContext: modelContext)
            if let book = try? bookService.getBook(withTitle: idea.bookTitle) {
                bookId = book.id.uuidString
            } else {
                bookId = idea.bookTitle
                print("WARNING: Could not find book for idea '\(idea.id)', using title as bookId")
            }
        }
        
        let coverageService = CoverageService(modelContext: modelContext)
        ideaCoverage = coverageService.getCoverage(for: idea.id, bookId: bookId)
        
        print("DEBUG: Loaded coverage for inactive idea \(idea.id): \(ideaCoverage?.coveragePercentage ?? 0)%, categories: \(ideaCoverage?.coveredCategories.count ?? 0)")
    }
}
