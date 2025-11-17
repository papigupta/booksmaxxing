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
    @State private var showingBookSelectionLab = false
    @State private var showingExperiments = false
    @State private var showingOverflow = false
    @State private var experimentsPreset: ThemePreset = .system
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
                
                // Fixed Footer Button (Palette-aware Primary 3D button)
                if !viewModel.extractedIdeas.isEmpty {
                    Button(action: {
                        print("DEBUG: Start Practicing button tapped")
                        showingDailyPractice = true
                    }) {
                        Text("Start Practicing")
                            .frame(maxWidth: .infinity)
                    }
                    .dsPalettePrimaryButton()
                    .padding(.horizontal, 0)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
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
        .sheet(isPresented: $showingBookSelectionLab) {
            BookSelectionDevToolsView(openAIService: openAIService)
        }
        .sheet(isPresented: $showingExperiments) {
            ThemeLabView(preset: $experimentsPreset)
                .environmentObject(themeManager)
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
        // Map coverage to palette-derived colors
        let tokens = themeManager.currentTokens(for: colorScheme)
        switch coverage {
        case 0..<25:
            return tokens.divider
        case 25..<50:
            return tokens.primary.opacity(0.6)
        case 50..<75:
            return tokens.primary.opacity(0.8)
        case 75..<100:
            return tokens.primary
        case 100:
            return tokens.secondary
        default:
            return tokens.divider
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top row with home button, streak, and overflow menu
            HStack {
                // Home Button - now palette secondary icon-only with book icon
                Button(action: {
                    // Use NavigationState to navigate back to book selection
                    navigationState.navigateToBookSelection()
                }) {
                    DSIcon("book.closed.fill", size: 14)
                }
                .dsPaletteSecondaryIconButton(diameter: 38)
                .accessibilityLabel("Select another book")
                
                Spacer()

                // Streak indicator
                StreakIndicatorView()

                // Overflow actions as a confirmation dialog, triggered by a palette secondary icon button
                Button(action: { showingOverflow = true }) {
                    DSIcon("ellipsis", size: 14)
                }
                .dsPaletteSecondaryIconButton(diameter: 38)
                .accessibilityLabel("More options")
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
                        .font(DS.Typography.title2)
                        .tracking(DS.Typography.tightTracking(for: 20))
                        .foregroundColor(
                            themeManager.activeRoles.color(role: .primary, tone: 30)
                            ?? themeManager.currentTokens(for: colorScheme).onSurface
                        )
                        .lineLimit(2)
                    
                    if let author = viewModel.bookInfo?.author {
                        Text("by \(author)")
                            .font(DS.Typography.fraunces(size: 14, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 14))
                            .padding(.top, 4)
                            .lineLimit(1)
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? themeManager.currentTokens(for: colorScheme).onSurface
                            )
                    } else {
                        Text("Author not specified")
                            .font(DS.Typography.fraunces(size: 14, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 14))
                            .padding(.top, 4)
                            .lineLimit(1)
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? themeManager.currentTokens(for: colorScheme).onSurface
                            )
                    }
                    
                    // Book description (match BookSelectionView text properties)
                    if let description = viewModel.currentBook?.bookDescription, !description.isEmpty {
                        Text(description)
                            .font(DS.Typography.fraunces(size: 12, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 12))
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? themeManager.currentTokens(for: colorScheme).onSurface
                            )
                            .lineLimit(4)
                            .padding(.top, DS.Spacing.xs)
                    }
                    
                    // Show rating if available
                    if let rating = viewModel.currentBook?.averageRating,
                       let ratingsCount = viewModel.currentBook?.ratingsCount {
                        HStack(spacing: DS.Spacing.xxs) {
                            let tokens = themeManager.currentTokens(for: colorScheme)
                            ForEach(0..<5) { index in
                                Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                    .font(.system(size: 12))
                                    .foregroundColor(tokens.secondary)
                            }
                            Text("(\(ratingsCount))")
                                .font(DS.Typography.caption)
                                .foregroundColor(tokens.onSurface.opacity(0.6))
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
        // Overflow actions dialog (replaces previous Menu)
        .confirmationDialog("Options", isPresented: $showingOverflow, titleVisibility: .visible) {
            if let book = viewModel.currentBook {
                let bookId = book.id.uuidString
                let rq = ReviewQueueManager(modelContext: modelContext)
                let stats = rq.getQueueStatistics(bookId: bookId)
                let count = stats.totalMCQs + stats.totalOpenEnded
                if count > 0 {
                    Button("Review Practice (\(count))") { showingDailyPractice = true }
                }
                if DebugFlags.enableDevControls {
                    Button("Refresh from Cloud") { CloudSyncRefresh(modelContext: modelContext).warmFetches() }
                    Button("Force Curveball Due") {
                        let service = CurveballService(modelContext: modelContext)
                        service.forceAllCurveballsDue(bookId: bookId, bookTitle: book.title)
                    }
                    Button("Book Selection Lab") { showingBookSelectionLab = true }
                    Button("Reset add-book tooltip") {
                        UserDefaults.standard.set(false, forKey: BookSelectionEducationKeys.addBookTipAcknowledged)
                    }
                    if DebugFlags.enableThemeLab { Button("Experiments") { showingExperiments = true } }
                }
                Button("Reset Today's Streak", role: .destructive) {
                    let didReset = streakManager.resetTodayActivity()
                    if didReset {
                        print("DEBUG: Manual streak reset from BookOverviewView")
                    } else {
                        print("DEBUG: Streak reset skipped — no activity recorded for today")
                    }
                }
                Button("Delete this book", role: .destructive) { showingDeleteAlert = true }
            }
            Button("Profile") { showingProfile = true }
            Button("Debug Info") { showingDebugInfo = true }
            Button("Log out", role: .destructive) {
                authManager.signOut()
                navigationState.shouldShowBookSelection = false
            }
        }
    }
}

// MARK: - Unified Idea List Item
struct UnifiedIdeaListItem: View {
    let idea: Idea
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var ideaCoverage: IdeaCoverage?
    
    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            // Left: Idea Title
            VStack(alignment: .leading, spacing: 2) {
                Text(idea.title)
                    .font(DS.Typography.caption)
                    .fontWeight(.light)
                    .lineLimit(2)
                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Center: Coverage Percentage / Mastery
            VStack(alignment: .center, spacing: 4) {
                if let coverage = ideaCoverage, coverage.coveragePercentage > 0 {
                    Text(coverage.curveballPassed ? "Mastered" : "\(Int(coverage.coveragePercentage))%")
                        .font(DS.Typography.caption)
                        .fontWeight(.light)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface)
                    
                    ProgressView(value: coverage.coveragePercentage / 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: coverageColor))
                        .frame(width: 60, height: 3)
                } else {
                    Text("0%")
                        .font(DS.Typography.caption)
                        .fontWeight(.light)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.6))
                    
                    ProgressView(value: 0)
                        .progressViewStyle(LinearProgressViewStyle(tint: themeManager.currentTokens(for: colorScheme).divider))
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
                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(index < importanceLevel.barCount ? themeManager.currentTokens(for: colorScheme).primary : themeManager.currentTokens(for: colorScheme).divider)
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
                .foregroundColor(themeManager.currentTokens(for: colorScheme).divider),
            alignment: .bottom
        )
        .onAppear {
            loadCoverageData()
        }
    }
    
    private var coverageColor: Color {
        // Use the book's extracted palette consistently
        let tokens = themeManager.currentTokens(for: colorScheme)
        return tokens.primary
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
