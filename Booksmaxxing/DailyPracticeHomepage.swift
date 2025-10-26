import SwiftUI
import SwiftData

@MainActor
struct DailyPracticeHomepage: View {
    let book: Book
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var practiceStats: PracticeStats?
    @State private var currentLessonNumber: Int = 0
    @State private var selectedLesson: GeneratedLesson? = nil
    @State private var refreshID = UUID()
    
    // Real lessons generated from book ideas
    @State private var practiceMilestones: [PracticeMilestone] = []
    @State private var generatedLessons: [GeneratedLesson] = []
    
    // Review queue tracking
    @State private var reviewQueueCount: Int? = nil
    @State private var hasReviewItems: Bool = false
    // Loading guards
    @State private var didInitialLoad: Bool = false
    @State private var isLoading: Bool = false
    @State private var showingOverflow: Bool = false
    
    private var lessonStorage: LessonStorageService {
        LessonStorageService(modelContext: modelContext)
    }
    
    private var lessonGenerator: LessonGenerationService {
        LessonGenerationService(
            modelContext: modelContext,
            openAIService: openAIService
        )
    }
    
    private var coverageService: CoverageService {
        CoverageService(modelContext: modelContext)
    }
    
    private var reviewQueueManager: ReviewQueueManager {
        ReviewQueueManager(modelContext: modelContext)
    }
    
    private var curveballService: CurveballService {
        CurveballService(modelContext: modelContext)
    }
    
    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: DS.Spacing.lg) {
                    // Header
                    headerSection
                    
                    // Practice Stats Overview
                    if let stats = practiceStats {
                        statsSection(stats)
                    }
                    
                    // Practice Path
                    practicePathSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            .id(refreshID)
            .navigationBarHidden(true)
            .background(theme.background)
            .confirmationDialog("Options", isPresented: $showingOverflow, titleVisibility: .visible) {
                if hasReviewItems {
                    Button(action: {
                        let reviewLesson = GeneratedLesson(
                            lessonNumber: -1,
                            title: "Review Practice",
                            primaryIdeaId: "",
                            primaryIdeaTitle: "Mixed Review",
                            reviewIdeaIds: [],
                            mistakeCorrections: [],
                            questionDistribution: QuestionDistribution(newQuestions: 0, reviewQuestions: 4, correctionQuestions: 0),
                            estimatedMinutes: 10,
                            isUnlocked: true,
                            isCompleted: false
                        )
                        selectedLesson = reviewLesson
                    }) { Text("Review Practice\(reviewQueueCount.map { " (\($0))" } ?? "")") }
                }
                if DebugFlags.enableDevControls {
                    Button("Force Curveball Due") {
                        let bookId = book.id.uuidString
                        curveballService.forceAllCurveballsDue(bookId: bookId, bookTitle: book.title)
                        refreshView()
                    }
                    Button("Force Spaced Follow‑up Due") {
                        let bookId = book.id.uuidString
                        let spacedService = SpacedFollowUpService(modelContext: modelContext)
                        spacedService.forceAllSpacedFollowUpsDue(bookId: bookId, bookTitle: book.title)
                        refreshView()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                isLoading = true
                await loadPracticeData()
                await prefetchCurrentLessonIfNeeded()
                didInitialLoad = true
                isLoading = false
            }
            .onAppear {
                Task { await themeManager.activateTheme(for: book) }
                // Avoid duplicate loads that cause visible flicker
                if !didInitialLoad {
                    Task {
                        isLoading = true
                        await loadPracticeData()
                        await prefetchCurrentLessonIfNeeded()
                        didInitialLoad = true
                        isLoading = false
                    }
                }
            }
            .onChange(of: refreshID) { _, newValue in
                // Force reload when refresh is triggered
                Task {
                    await loadPracticeData()
                }
            }
            .fullScreenCover(item: $selectedLesson) { lesson in
                // If lesson number exceeds total ideas, treat as review-only session
                let totalIdeas = (book.ideas ?? []).count
                if lesson.lessonNumber > totalIdeas {
                    // Use the new review-enabled practice view
                    DailyPracticeWithReviewView(
                        book: book,
                        openAIService: openAIService,
                        selectedLesson: lesson,
                        onPracticeComplete: {
                            print("DEBUG: ✅✅ Review practice complete")
                            // Mark this review-only lesson as completed so the next (17, 18, …) can appear
                            completeLesson(lesson)
                            selectedLesson = nil
                            refreshView()
                        }
                    )
                } else {
                    // Use the regular lesson view
                    DailyPracticeView(
                        book: book,
                        openAIService: openAIService,
                        practiceType: .quick,
                        selectedLesson: lesson,
                        onPracticeComplete: {
                            print("DEBUG: ✅✅ onPracticeComplete callback triggered for lesson \(lesson.lessonNumber)")
                            // Mark lesson as completed and unlock next lesson
                        completeLesson(lesson)
                        // Dismiss after completion
                        selectedLesson = nil
                        // Force refresh
                        refreshID = UUID()
                        print("DEBUG: ✅✅ Refreshing view after lesson completion")
                    }
                )
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        let tokens = themeManager.currentTokens(for: colorScheme)
        let totalIdeas = (book.ideas ?? []).count
        return VStack(alignment: .leading, spacing: 0) {
            // Top row: back button • streak • overflow
            HStack {
                // Back to Book (icon-only, palette secondary)
                Button(action: { dismiss() }) {
                    DSIcon("book.closed.fill", size: 14)
                }
                .dsPaletteSecondaryIconButton(diameter: 38)
                .accessibilityLabel("Back to Book")

                Spacer()

                // Streak indicator
                StreakIndicatorView()

                // Overflow actions trigger (palette secondary icon button)
                Button(action: { showingOverflow = true }) {
                    DSIcon("ellipsis", size: 14)
                }
                .dsPaletteSecondaryIconButton(diameter: 38)
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.md)

            // Book cover, title, author, description (match BookOverviewView)
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // Book Cover
                if book.coverImageUrl != nil || book.thumbnailUrl != nil {
                    BookCoverView(
                        thumbnailUrl: book.thumbnailUrl,
                        coverUrl: book.coverImageUrl,
                        isLargeView: false
                    )
                    .frame(width: 80, height: 120)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                }

                // Book title and author
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(book.title)
                        .font(DS.Typography.title2)
                        .tracking(DS.Typography.tightTracking(for: 20))
                        .foregroundColor(
                            themeManager.activeRoles.color(role: .primary, tone: 30)
                            ?? tokens.onSurface
                        )
                        .lineLimit(2)

                    if let author = book.author {
                        Text("by \(author)")
                            .font(DS.Typography.fraunces(size: 14, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 14))
                            .padding(.top, 4)
                            .lineLimit(1)
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? tokens.onSurface
                            )
                    } else {
                        Text("Author not specified")
                            .font(DS.Typography.fraunces(size: 14, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 14))
                            .padding(.top, 4)
                            .lineLimit(1)
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? tokens.onSurface
                            )
                    }

                    // Book description (match BookOverviewView text properties)
                    if let description = book.bookDescription, !description.isEmpty {
                        Text(description)
                            .font(DS.Typography.fraunces(size: 12, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 12))
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? tokens.onSurface
                            )
                            .lineLimit(4)
                            .padding(.top, DS.Spacing.xs)
                    }

                    // Show rating if available
                    if let rating = book.averageRating,
                       let ratingsCount = book.ratingsCount {
                        HStack(spacing: DS.Spacing.xxs) {
                            let t = tokens
                            ForEach(0..<5) { index in
                                Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                    .font(.system(size: 12))
                                    .foregroundColor(t.secondary)
                            }
                            Text("(\(ratingsCount))")
                                .font(DS.Typography.caption)
                                .foregroundColor(t.onSurface.opacity(0.6))
                        }
                        .padding(.top, DS.Spacing.xxs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, DS.Spacing.sm)

            // Book Coverage Display (full-width)
            if totalIdeas > 0 {
                bookCoverageView
            }
        }
        .background(tokens.surface)
    }

    // MARK: - Book Coverage View (match BookOverviewView)
    @ViewBuilder
    private var bookCoverageView: some View {
        let bookId = book.id.uuidString
        let totalIdeas = (book.ideas ?? []).count
        let coverageService = CoverageService(modelContext: modelContext)
        let bookCoverage = coverageService.calculateBookCoverage(bookId: bookId, totalIdeas: totalIdeas)

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
    
    // MARK: - Stats Section
    private func statsSection(_ stats: PracticeStats) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Your Progress")
                .font(DS.Typography.headline)
                .foregroundColor(theme.onSurface)
            
            HStack(spacing: DS.Spacing.md) {
                StatCard(
                    icon: "brain.head.profile",
                    title: "New Ideas",
                    value: "\(stats.newIdeasCount)",
                    subtitle: "Ready to learn"
                )
                
                StatCard(
                    icon: "arrow.clockwise",
                    title: "Review",
                    value: "\(stats.reviewDueCount)",
                    subtitle: "Due today"
                )
                
                StatCard(
                    icon: "star.fill",
                    title: "Mastered",
                    value: "\(stats.masteredCount)",
                    subtitle: "Concepts"
                )
            }
        }
        .padding(DS.Spacing.md)
        .background(theme.surfaceVariant)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.outline, lineWidth: DS.BorderWidth.thin))
        .cornerRadius(8)
    }
    
    // MARK: - Practice Path Section
    private var practicePathSection: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Your Learning Path")
                .font(DS.Typography.headline)
                .foregroundColor(theme.onSurface)
            
            if practiceMilestones.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text("Loading lessons…")
                        .font(DS.Typography.body)
                        .foregroundColor(theme.onSurface.opacity(0.7))
                }
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: DS.Spacing.lg) {
                            ForEach(Array(practiceMilestones.enumerated()), id: \.element.id) { index, milestone in
                            VStack(spacing: DS.Spacing.sm) {
                                MilestoneNode(
                                    milestone: milestone,
                                    lesson: nil, // No longer pre-generating lessons
                                    onTap: {
                                        print("DEBUG: Tapped on lesson \(milestone.id), isCurrent: \(milestone.isCurrent), isCompleted: \(milestone.isCompleted)")
                                        
                                        let totalIdeas = (book.ideas ?? []).count
                                        if milestone.id > totalIdeas {
                                            // Review-only lesson: create a placeholder GeneratedLesson and present review view
                                            print("DEBUG: Starting review-only session for lesson \(milestone.id)")
                                            // Ensure a StoredLesson exists so we can mark completion
                                            let _ = lessonStorage.getOrCreateReviewLesson(bookId: book.id.uuidString, lessonNumber: milestone.id, book: book)
                                            let tempLesson = GeneratedLesson(
                                                lessonNumber: milestone.id,
                                                title: "Review Practice",
                                                primaryIdeaId: "review_session",
                                                primaryIdeaTitle: "Review Practice",
                                                reviewIdeaIds: [],
                                                mistakeCorrections: [],
                                                questionDistribution: QuestionDistribution(newQuestions: 0, reviewQuestions: 8, correctionQuestions: 0),
                                                estimatedMinutes: 12,
                                                isUnlocked: true,
                                                isCompleted: false
                                            )
                                            selectedLesson = tempLesson
                                        } else {
                                            // Normal idea lesson
                                            let bookId = book.id.uuidString
                                            guard let lessonInfo = lessonStorage.getLessonInfo(bookId: bookId, lessonNumber: milestone.id, book: book) else {
                                                print("ERROR: Could not get lesson info for lesson \(milestone.id)")
                                                return
                                            }
                                            if lessonInfo.isUnlocked {
                                                print("DEBUG: Starting lesson generation for lesson \(milestone.id)")
                                                let emptyMistakeCorrections: [(ideaId: String, concepts: [String])] = []
                                                let sortedIdeas = (book.ideas ?? []).sortedByNumericId()
                                                let primaryIdeaId = sortedIdeas[milestone.id - 1].id
                                                let tempLesson = GeneratedLesson(
                                                    lessonNumber: milestone.id,
                                                    title: "Lesson \(milestone.id): \(lessonInfo.title)",
                                                    primaryIdeaId: primaryIdeaId,
                                                    primaryIdeaTitle: lessonInfo.title,
                                                    reviewIdeaIds: [],
                                                    mistakeCorrections: emptyMistakeCorrections,
                                                    questionDistribution: QuestionDistribution(newQuestions: 8, reviewQuestions: 0, correctionQuestions: 0),
                                                    estimatedMinutes: 10,
                                                    isUnlocked: true,
                                                    isCompleted: lessonInfo.isCompleted
                                                )
                                                selectedLesson = tempLesson
                                            } else {
                                                print("DEBUG: Lesson \(milestone.id) is not unlocked")
                                            }
                                        }
                                    }
                                )
                                .id(milestone.id)
                                
                                // Connection line (except for last item)
                                if index < practiceMilestones.count - 1 {
                                    Rectangle()
                                        .fill(milestone.isCompleted ? DS.Colors.black : DS.Colors.gray300)
                                        .frame(width: 2, height: 30)
                                }
                            }
                        }
                    }
                    .padding(.vertical, DS.Spacing.md)
                    .onChange(of: practiceMilestones) { _, _ in
                        // Recenter when milestones update (e.g., after completing a review-only session)
                        scrollToCurrentLesson(proxy: proxy)
                    }
                }
                .frame(maxHeight: 400)
                .onAppear {
                    // Scroll to current lesson (Today's Focus)
                    scrollToCurrentLesson(proxy: proxy)
                }
            }
        }
            }
    }
    
    
    // MARK: - Helper Methods
    private func scrollToCurrentLesson(proxy: ScrollViewProxy) {
        if let currentMilestone = practiceMilestones.first(where: { $0.isCurrent }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(currentMilestone.id, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Lesson Management
    private func completeLesson(_ lesson: GeneratedLesson) {
        print("DEBUG: ✅ Completing lesson \(lesson.lessonNumber)")
        
        let bookId = book.id.uuidString
        
        // Mark the lesson as completed (using UserDefaults for reliability)
        lessonStorage.markLessonCompleted(bookId: bookId, lessonNumber: lesson.lessonNumber, book: book)
        // Count toward daily streak (idempotent per day)
        streakManager.markActivity()
        
        // Note: We're NOT using mastery for completion anymore
        // Completion = user attempted all questions, regardless of accuracy
        print("DEBUG: Lesson \(lesson.lessonNumber) marked as completed (user attempted all questions)")
        
        // Reload practice data to refresh stats and milestones
        // This will automatically set the next lesson as current
        Task {
            await loadPracticeData()
            print("DEBUG: ✅ Reloaded practice data - should now show lesson \(lesson.lessonNumber + 1) as current")
            // Prefetch next lesson in background (lessonNumber + 1)
            await prefetchLesson(number: lesson.lessonNumber + 1)
        }
    }
    
    // MARK: - Data Loading
    private func refreshView() {
        refreshID = UUID()
        Task {
            await loadPracticeData()
        }
    }
    
    private func loadPracticeData() async {
        let bookId = book.id.uuidString
        // Ensure any due curveballs and spacedfollowups are queued for this book before computing stats
        curveballService.ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: book.title)
        let spacedService = SpacedFollowUpService(modelContext: modelContext)
        spacedService.ensureSpacedFollowUpsQueuedIfDue(bookId: bookId, bookTitle: book.title)
        
        // Get lesson info for display (no actual generation yet)
        let lessonInfos = lessonStorage.getAllLessonInfo(book: book)
        
        // Find the first incomplete lesson (this will be the current lesson)
        var currentLessonNumber = 1
        var foundIncomplete = false
        
        for info in lessonInfos {
            if !info.isCompleted && info.isUnlocked {
                currentLessonNumber = info.lessonNumber
                foundIncomplete = true
                print("DEBUG: Found incomplete lesson \(info.lessonNumber) as current")
                break
            }
        }
        
        // If all unlocked lessons are completed, the current lesson stays at the last one
        if !foundIncomplete {
            // Find the last completed lesson
            for info in lessonInfos.reversed() {
                if info.isCompleted {
                    currentLessonNumber = min(info.lessonNumber + 1, lessonInfos.count)
                    print("DEBUG: All unlocked lessons completed, setting current to lesson \(currentLessonNumber)")
                    break
                }
            }
        }
        
        print("DEBUG: Current lesson number after logic: \(currentLessonNumber)")
        print("DEBUG: Retrieved \(lessonInfos.count) lesson infos from LessonStorage")
        
        // Convert to milestones for UI
        var milestones = lessonInfos.enumerated().map { index, info in
            let isCurrent = info.lessonNumber == currentLessonNumber && info.isUnlocked && !info.isCompleted
            print("DEBUG: Creating milestone - Lesson \(info.lessonNumber): \(info.title), Unlocked: \(info.isUnlocked), Completed: \(info.isCompleted), Current: \(isCurrent)")
            return PracticeMilestone(
                id: info.lessonNumber,
                title: info.title,
                isCompleted: info.isCompleted,
                isCurrent: isCurrent
            )
        }

        // Load review queue stats for this specific book (after ensuring curveballs/spacedfollowups queued)
        let queueStats = reviewQueueManager.getQueueStatistics(bookId: book.id.uuidString)
        let totalReviewItems = queueStats.totalMCQs + queueStats.totalOpenEnded
        
        // Calculate practice stats
        let ideas = (book.ideas ?? [])
        
        var newIdeasCount = 0
        let reviewDueCount = totalReviewItems  // Use actual queue count
        var masteredCount = 0
        
        for idea in ideas {
            let coverage = coverageService.getCoverage(for: idea.id, bookId: bookId)

            if coverage.coveragePercentage == 0 {
                newIdeasCount += 1
            } else if (coverage.spacedFollowUpPassedAt != nil) && coverage.curveballPassed {
                // Mastery requires both full coverage and passing the curveball
                masteredCount += 1
            }
        }
        
        // If all idea lessons completed, append all review-only lessons and choose current properly
        let totalIdeas = (book.ideas ?? []).count
        let allIdeasCompleted = lessonInfos.last.map { $0.isCompleted } ?? false
        if allIdeasCompleted {
            // Fetch all review-only StoredLesson rows for this book
            let descriptor = FetchDescriptor<StoredLesson>(
                predicate: #Predicate<StoredLesson> { l in l.bookId == bookId && l.lessonNumber > totalIdeas },
                sortBy: [SortDescriptor(\.lessonNumber)]
            )
            let existingReviewLessons: [StoredLesson] = (try? modelContext.fetch(descriptor)) ?? []

            // Append all existing review-only lessons so completed ones remain visible
            for rl in existingReviewLessons {
                milestones.append(
                    PracticeMilestone(
                        id: rl.lessonNumber,
                        title: "Review Practice",
                        isCompleted: rl.isCompleted,
                        isCurrent: false
                    )
                )
            }

            // Decide which review milestone is current
            if let firstIncomplete = existingReviewLessons.first(where: { !$0.isCompleted }) {
                if let idx = milestones.firstIndex(where: { $0.id == firstIncomplete.lessonNumber }) {
                    milestones[idx].isCurrent = true
                    currentLessonNumber = firstIncomplete.lessonNumber
                }
            } else if totalReviewItems > 0 {
                // No incomplete stored review lessons; if review items are due, show the next one
                let nextId = (existingReviewLessons.last?.lessonNumber ?? totalIdeas) + 1
                milestones.append(
                    PracticeMilestone(
                        id: nextId,
                        title: "Review Practice",
                        isCompleted: false,
                        isCurrent: true
                    )
                )
                currentLessonNumber = nextId
            }
        }

        await MainActor.run {
            print("DEBUG: Setting practiceMilestones array with \(milestones.count) milestones")
            self.practiceMilestones = milestones
            print("DEBUG: practiceMilestones.count after setting: \(self.practiceMilestones.count)")
            
            self.practiceStats = PracticeStats(
                newIdeasCount: newIdeasCount,
                reviewDueCount: reviewDueCount,
                masteredCount: masteredCount
            )
            
            // Update review queue state
            self.reviewQueueCount = totalReviewItems
            self.hasReviewItems = totalReviewItems > 0
            
            print("🎯 REVIEW BUTTON DEBUG: count=\(totalReviewItems), hasReviewItems=\(totalReviewItems > 0)")
            
            self.currentLessonNumber = currentLessonNumber
            
            print("DEBUG: Loaded \(milestones.count) lesson infos from \(ideas.count) ideas")
            print("DEBUG: Current lesson: \(currentLessonNumber)")
            print("DEBUG: First milestone - ID: \(milestones.first?.id ?? 0), Current: \(milestones.first?.isCurrent ?? false), Completed: \(milestones.first?.isCompleted ?? false)")
            print("DEBUG: Stats - New: \(newIdeasCount), Review: \(reviewDueCount), Mastered: \(masteredCount)")
        }
    }

    // MARK: - Prefetch helpers
    private func prefetchCurrentLessonIfNeeded() async {
        // Identify current lesson from milestones
        guard let current = practiceMilestones.first(where: { $0.isCurrent }) else { return }
        // Only prefetch mixed idea lessons; review-only sessions are generated on demand
        let totalIdeas = (book.ideas ?? []).count
        if current.id <= totalIdeas {
            await prefetchLesson(number: current.id)
            // Prewarm only the initial 8 for the next lesson; reviews depend on results of current.
            let next = min(current.id + 1, practiceMilestones.count)
            if next != current.id {
                let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
                prefetcher.prewarmInitialQuestions(book: book, lessonNumber: next)
            }
        }
    }

    private func prefetchLesson(number: Int) async {
        let prefetcher = PracticePrefetcher(modelContext: modelContext, openAIService: openAIService)
        prefetcher.prefetchLesson(book: book, lessonNumber: number)
    }

    // MARK: - Quick Prefill to Avoid Flicker
    private func quickPrefillMilestones() {
        let lessonInfos = lessonStorage.getAllLessonInfo(book: book)
        var currentLessonNumber = 1
        if let firstIncomplete = lessonInfos.first(where: { !$0.isCompleted && $0.isUnlocked }) {
            currentLessonNumber = firstIncomplete.lessonNumber
        } else if let last = lessonInfos.last {
            currentLessonNumber = min(last.lessonNumber + 1, lessonInfos.count)
        }
        self.practiceMilestones = lessonInfos.map { info in
            PracticeMilestone(
                id: info.lessonNumber,
                title: info.title,
                isCompleted: info.isCompleted,
                isCurrent: info.lessonNumber == currentLessonNumber && info.isUnlocked && !info.isCompleted
            )
        }
    }
}

// MARK: - Supporting Views
private struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(theme.primary)
            
            Text(value)
                .font(DS.Typography.headline)
                .foregroundColor(theme.onSurface)
            
            Text(title)
                .font(DS.Typography.caption)
                .foregroundColor(theme.onSurface.opacity(0.7))
            
            Text(subtitle)
                .font(DS.Typography.small)
                .foregroundColor(theme.onSurface.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.sm)
        .background(theme.surfaceVariant)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.outline, lineWidth: DS.BorderWidth.hairline))
        .cornerRadius(6)
    }
}

private struct MilestoneNode: View {
    let milestone: PracticeMilestone
    let lesson: GeneratedLesson?
    let onTap: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                // Milestone circle
                ZStack {
                    Circle()
                        .fill(circleColor(theme))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(strokeColor(theme), lineWidth: milestone.isCurrent ? 3 : 1)
                        )
                        .scaleEffect(milestone.isCurrent ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: milestone.isCurrent)
                    
                    // Icon or lesson number
                    if milestone.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(theme.onSecondary)
                    } else if milestone.isCurrent {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(theme.onPrimary)
                    } else {
                        Text("\(milestone.id)")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(theme.onSurface.opacity(0.6))
                    }
                }
                
                // Lesson info
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Lesson \(milestone.id)")
                        .font(DS.Typography.caption)
                        .foregroundColor(theme.onSurface.opacity(0.7))
                    
                    Text(milestone.title)
                        .font(DS.Typography.bodyBold)
                        .foregroundColor(milestone.isCurrent ? theme.onPrimaryContainer : (milestone.isCompleted ? theme.onSecondaryContainer : theme.onSurface.opacity(0.7)))
                }
                
                Spacer()
                
                // Status indicator
                if milestone.isCurrent {
                    Text("START")
                        .font(DS.Typography.small)
                        .fontWeight(.bold)
                        .foregroundColor(theme.onPrimary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(theme.primary)
                        .cornerRadius(12)
                }
            }
            .padding(DS.Spacing.md)
            .background(milestone.isCurrent ? theme.primaryContainer.opacity(0.25) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(milestone.isCurrent ? theme.outline : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!milestone.isCompleted && !milestone.isCurrent)
    }
    
    private func circleColor(_ theme: ThemeTokens) -> Color {
        if milestone.isCompleted {
            return theme.secondary
        } else if milestone.isCurrent {
            return theme.primary
        } else {
            return theme.surfaceVariant
        }
    }
    
    private func strokeColor(_ theme: ThemeTokens) -> Color {
        if milestone.isCompleted {
            return theme.onSecondary.opacity(0.3)
        } else if milestone.isCurrent {
            return theme.onPrimary.opacity(0.3)
        } else {
            return theme.outline
        }
    }
}

// MARK: - Data Models
struct PracticeStats {
    let newIdeasCount: Int
    let reviewDueCount: Int
    let masteredCount: Int
}

struct PracticeMilestone: Equatable {
    let id: Int
    let title: String
    var isCompleted: Bool
    var isCurrent: Bool
}

enum PracticeType {
    case quick      // 1 new + 2 review, ~5-10 min
    case focused    // 2 new + 3 review, ~15-20 min  
    case review     // Only review items, variable length
}
