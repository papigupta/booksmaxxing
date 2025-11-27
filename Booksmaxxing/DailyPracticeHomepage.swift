import SwiftUI
import SwiftData

@MainActor
struct DailyPracticeHomepage: View {
    let book: Book
    let openAIService: OpenAIService
    let isRootExperience: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var currentLessonNumber: Int = 0
    @State private var selectedLesson: GeneratedLesson? = nil
    @State private var refreshID = UUID()
    @State private var showingIdeaResponses = false
    @State private var selectedIdea: Idea? = nil
    @State private var showingSafari = false
    @State private var safariURL: URL? = nil
    @State private var stickyHeaderHeight: CGFloat = Layout.initialStickyHeaderHeight
    
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
    @State private var showingBookSelectionLab: Bool = false
    @State private var showingExperiments: Bool = false
    @State private var experimentsPreset: ThemePreset = .system
    @State private var showingDeleteAlert: Bool = false
    @State private var pendingScrollTask: Task<Void, Never>? = nil
    
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
    
    init(book: Book, openAIService: OpenAIService, isRootExperience: Bool = false) {
        self.book = book
        self.openAIService = openAIService
        self.isRootExperience = isRootExperience
    }


    var body: some View {
        let tokens = themeManager.currentTokens(for: colorScheme)
        let roles = themeManager.activeRoles
        // Favor the second extracted seed color for current lesson accents, falling back gracefully
        let seedColor = themeManager.seedColor(at: 1) ?? themeManager.seedColor(at: 0)
        let palette = PracticePalette(roles: roles, seedColor: seedColor, tokens: tokens)
        return NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ZStack(alignment: .top) {
                        ScrollView(.vertical, showsIndicators: false) {
                            practiceTimelineSection(palette: palette)
                                .padding(.horizontal, Layout.horizontalPadding)
                                .padding(.top, stickyHeaderHeight + Layout.timelineTopInset)
                                .padding(.bottom, Layout.bottomPadding)
                        }
                        .id(refreshID)

                        stickyHeader(palette: palette, tokens: tokens, safeTopInset: geometry.safeAreaInsets.top)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: StickyHeaderHeightPreference.self, value: proxy.size.height)
                                }
                            )
                    }
                    .onPreferenceChange(StickyHeaderHeightPreference.self) { height in
                        guard height > 0 else { return }
                        Task { @MainActor in stickyHeaderHeight = height }
                    }
                    .background(backgroundGradient(palette: palette).ignoresSafeArea())
                    .navigationBarHidden(true)
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
                        Button("Force Curveball Due") {
                            let bookId = book.id.uuidString
                            curveballService.forceAllCurveballsDue(bookId: bookId, bookTitle: book.title)
                            refreshView()
                        }
                        Button("Force Spaced Follow-up Due") {
                            let bookId = book.id.uuidString
                            let spacedService = SpacedFollowUpService(modelContext: modelContext)
                            spacedService.forceAllSpacedFollowUpsDue(bookId: bookId, bookTitle: book.title)
                            refreshView()
                        }
                        Button("Refresh from Cloud") {
                            CloudSyncRefresh(modelContext: modelContext).warmFetches()
                        }
                        Button("Book Selection Lab") { showingBookSelectionLab = true }
                        Button("Reset add-book tooltip") {
                            UserDefaults.standard.set(false, forKey: BookSelectionEducationKeys.addBookTipAcknowledged)
                        }
                        if DebugFlags.enableThemeLab {
                            Button("Experiments") { showingExperiments = true }
                        }
                        Button("Delete this book", role: .destructive) {
                            showingDeleteAlert = true
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
                        scheduleScrollIfNeeded(proxy: proxy, animated: false)
                        Task { await themeManager.activateTheme(for: book) }
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
                    .onChange(of: refreshID) { _, _ in
                        Task { await loadPracticeData() }
                    }
                    .onChange(of: book.id) { _, _ in
                        resetForNewBook()
                    }
                    .onChange(of: practiceMilestones) { _, _ in
                        scheduleScrollIfNeeded(proxy: proxy)
                    }
                    .onChange(of: currentLessonNumber) { _, _ in
                        scheduleScrollIfNeeded(proxy: proxy)
                    }
                    .onChange(of: stickyHeaderHeight) { _, _ in
                        scheduleScrollIfNeeded(proxy: proxy, animated: false)
                    }
                    .fullScreenCover(item: $selectedLesson) { lesson in
                        let totalIdeas = (book.ideas ?? []).count
                        let presentedView: AnyView = {
                            if lesson.lessonNumber > totalIdeas {
                                return AnyView(
                                    DailyPracticeWithReviewView(
                                        book: book,
                                        openAIService: openAIService,
                                        selectedLesson: lesson,
                                        onPracticeComplete: {
                                            print("DEBUG: ✅✅ Review practice complete")
                                            completeLesson(lesson)
                                            selectedLesson = nil
                                            refreshView()
                                        }
                                    )
                                )
                            } else {
                                return AnyView(
                                    DailyPracticeView(
                                        book: book,
                                        openAIService: openAIService,
                                        practiceType: .quick,
                                        selectedLesson: lesson,
                                        onPracticeComplete: {
                                            print("DEBUG: ✅✅ onPracticeComplete callback triggered for lesson \(lesson.lessonNumber)")
                                            completeLesson(lesson)
                                            selectedLesson = nil
                                            refreshID = UUID()
                                            print("DEBUG: ✅✅ Refreshing view after lesson completion")
                                        }
                                    )
                                )
                            }
                        }()

                        if #available(iOS 17.0, *) {
                            presentedView
                                .presentationBackground(tokens.background)
                        } else {
                            presentedView
                        }
                    }
                    .sheet(isPresented: $showingSafari) {
                        if let safariURL {
                            SafariView(url: safariURL)
                        } else {
                            EmptyView()
                        }
                    }
                    .sheet(isPresented: $showingBookSelectionLab) {
                        BookSelectionDevToolsView(openAIService: openAIService)
                    }
                    .sheet(isPresented: $showingExperiments) {
                        ThemeLabView(preset: $experimentsPreset)
                            .environmentObject(themeManager)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showingIdeaResponses) {
            if let selectedIdea {
                IdeaResponsesView(idea: selectedIdea)
            } else {
                EmptyView()
            }
        }
        .alert("Delete \"\(book.title)\"?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteCurrentBook()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all data and progress for this book, including generated questions, practice sessions, coverage, review queue, primers, and your answers. This action cannot be undone.")
        }
        .onDisappear {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
        }
    }

    // MARK: - Header + Hero
    private func stickyHeader(palette: PracticePalette, tokens: ThemeTokens, safeTopInset: CGFloat) -> some View {
        let adjustedSafeInset = max(safeTopInset - Layout.safeInsetReduction, Layout.minimumSafeInset)

        return VStack(spacing: Layout.headerSpacing) {
            topControls(palette: palette)
                .padding(.top, adjustedSafeInset)

            heroSection(palette: palette)
                .padding(.top, Layout.heroTopPadding)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.bottom, Layout.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { stickyHeaderBackground(palette: palette, tokens: tokens) }
        .overlay(alignment: .bottom) { stickyHeaderBottomBorder(palette: palette) }
    }

    private func topControls(palette: PracticePalette) -> some View {
        HStack {
            Button(action: handlePrimaryNavigationTap) {
                DSIcon("book.closed.fill", size: 14)
            }
            .dsPaletteSecondaryIconButton(diameter: 38)
            .accessibilityLabel("Book selection")

            Spacer()

            StreakIndicatorView()

            Button(action: { showingOverflow = true }) {
                DSIcon("ellipsis", size: 14)
            }
            .dsPaletteSecondaryIconButton(diameter: 38)
            .accessibilityLabel("More options")
        }
    }
    
    private func heroSection(palette: PracticePalette) -> some View {
        VStack(alignment: .leading, spacing: Layout.heroSpacing) {
            HStack(alignment: .top, spacing: Layout.heroSpacing) {
                BookCoverView(
                    thumbnailUrl: book.thumbnailUrl,
                    coverUrl: book.coverImageUrl,
                    isLargeView: true,
                    cornerRadius: 12,
                    targetSize: Layout.coverSize
                )
                .frame(width: Layout.coverSize.width, height: Layout.coverSize.height)
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: Layout.titleAuthorSpacing) {
                        Text(book.title)
                            .font(DS.Typography.fraunces(size: 20, weight: .semibold))
                            .tracking(DS.Typography.tightTracking(for: 20))
                            .foregroundColor(palette.primaryT30)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)

                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(DS.Typography.fraunces(size: 14, weight: .regular))
                                .tracking(DS.Typography.tightTracking(for: 14))
                                .foregroundColor(palette.primaryT40)
                                .lineLimit(1)
                        }
                    }

                    if let description = book.bookDescription, !description.isEmpty {
                        Text(description)
                            .font(DS.Typography.fraunces(size: 12, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 12))
                            .foregroundColor(palette.primaryT50)
                            .lineLimit(6)
                    }

                    amazonButton(palette: palette)
                }
            }
        }
    }

    private func stickyHeaderBackground(palette: PracticePalette, tokens: ThemeTokens) -> some View {
        palette.flatBackground
            .ignoresSafeArea(edges: .top)
    }

    private func stickyHeaderBottomFade(palette: PracticePalette) -> some View {
        LinearGradient(
            colors: [
                palette.flatBackground,
                palette.flatBackground.opacity(0.0)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: Layout.headerFadeHeight)
        .allowsHitTesting(false)
    }

    private func stickyHeaderBottomBorder(palette: PracticePalette) -> some View {
        Rectangle()
            .fill(palette.primaryT40)
            .frame(height: Layout.headerBottomBorderWidth)
            .padding(.horizontal, Layout.horizontalPadding)
            .allowsHitTesting(false)
    }

    private func amazonButton(palette: PracticePalette) -> some View {
        Button(action: openAmazonLink) {
            HStack(spacing: 4) {
                Text("Buy on")
                    .font(DS.Typography.caption)
                    .foregroundColor(palette.primaryT40)
                Text("Amazon")
                    .font(DS.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.primaryT40)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(palette.background.opacity(0.6))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(palette.primaryT70)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func practiceTimelineSection(palette: PracticePalette) -> some View {
        VStack(alignment: .leading, spacing: Layout.timelineSpacing) {
            if isLoading && practiceMilestones.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text("Loading lessons…")
                        .font(DS.Typography.body)
                        .foregroundColor(palette.primaryT40.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DS.Spacing.md)
            } else if practiceMilestones.isEmpty {
                Text("No lessons yet. Start practicing to unlock your timeline.")
                    .font(DS.Typography.body)
                    .foregroundColor(palette.primaryT40)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: Layout.timelineSpacing) {
                    ForEach(Array(practiceMilestones.enumerated()), id: \.element.id) { index, milestone in
                        LessonCardView(
                            milestone: milestone,
                            palette: palette,
                            showConnector: index < practiceMilestones.count - 1,
                            onTap: { handleLessonSelection(milestone) }
                        )
                        .id(milestone.id)
                    }
                }
            }
        }
    }

    private func openAmazonLink() {
        guard let url = AmazonLinkBuilder.url(for: book) else { return }
        safariURL = url
        showingSafari = true
    }
    
    private func deleteCurrentBook() {
        let service = BookService(modelContext: modelContext)
        do {
            try service.deleteBookAndAllData(book: book)
            navigationState.navigateToBookSelection()
            if !isRootExperience {
                dismiss()
            }
        } catch {
            print("DEBUG: Failed to delete book from DailyPracticeHomepage: \(error)")
        }
    }

    private func resetForNewBook() {
        practiceMilestones = []
        currentLessonNumber = 0
        selectedLesson = nil
        showingIdeaResponses = false
        showingOverflow = false
        refreshID = UUID()

        Task {
            await themeManager.activateTheme(for: book)
            await loadPracticeData()
            await prefetchCurrentLessonIfNeeded()
        }
    }

    private func backgroundGradient(palette: PracticePalette) -> LinearGradient {
        LinearGradient(
            colors: [palette.flatBackground, palette.flatBackground],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func handleLessonSelection(_ milestone: PracticeMilestone) {
        if milestone.isCurrent {
            handleMilestoneTap(milestone: milestone)
        } else if let idea = milestone.idea {
            selectedIdea = idea
            showingIdeaResponses = true
        }
    }

    private func lessonMetrics(for idea: Idea, bookId: String) -> LessonMetrics {
        let coverage = coverageService.getCoverage(for: idea.id, bookId: bookId)
        let clarityValue: Double? = coverage.totalQuestionsSeen > 0 ? coverage.currentAccuracy : nil
        let attempts = (idea.tests ?? []).flatMap { $0.attempts ?? [] }
        let totalBCal = attempts.reduce(0) { $0 + max(0, $1.brainCalories) }
        return LessonMetrics(clarityPercent: clarityValue, brainCalories: totalBCal)
    }

    private func handlePrimaryNavigationTap() {
        navigationState.navigateToBookSelection()
        if !isRootExperience {
            dismiss()
        }
    }
    
    // MARK: - Helper Methods
    private func handleMilestoneTap(milestone: PracticeMilestone) {
        print("DEBUG: Tapped on lesson \(milestone.id), isCurrent: \(milestone.isCurrent), isCompleted: \(milestone.isCompleted)")
        if milestone.isReviewPractice {
            print("DEBUG: Starting review-only session for lesson \(milestone.id)")
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
            return
        }

        guard let idea = milestone.idea else {
            print("ERROR: Milestone \(milestone.id) missing idea reference")
            return
        }

        let bookId = book.id.uuidString
        guard let lessonInfo = lessonStorage.getLessonInfo(bookId: bookId, lessonNumber: milestone.id, book: book) else {
            print("ERROR: Could not get lesson info for lesson \(milestone.id)")
            return
        }

        guard lessonInfo.isUnlocked else {
            print("DEBUG: Lesson \(milestone.id) is not unlocked")
            return
        }

        print("DEBUG: Starting lesson generation for lesson \(milestone.id)")
        let tempLesson = GeneratedLesson(
            lessonNumber: milestone.id,
            title: "Lesson \(milestone.id): \(lessonInfo.title)",
            primaryIdeaId: idea.id,
            primaryIdeaTitle: idea.title,
            reviewIdeaIds: [],
            mistakeCorrections: [],
            questionDistribution: QuestionDistribution(newQuestions: 8, reviewQuestions: 0, correctionQuestions: 0),
            estimatedMinutes: 10,
            isUnlocked: true,
            isCompleted: lessonInfo.isCompleted
        )
        selectedLesson = tempLesson
    }
    
    private func scheduleScrollIfNeeded(proxy: ScrollViewProxy, animated: Bool = true) {
        guard shouldAutoScroll else { return }
        scrollToCurrentLesson(proxy: proxy, animated: animated)
    }

    private var shouldAutoScroll: Bool {
        guard let currentId = practiceMilestones.first(where: { $0.isCurrent })?.id,
              currentId > 3 else {
            return false
        }

        let firstThree = practiceMilestones.filter { $0.id <= 3 }
        guard firstThree.count == 3 else { return false }
        return firstThree.allSatisfy { $0.isCompleted }
    }

    private func scrollToCurrentLesson(proxy: ScrollViewProxy, animated: Bool = true) {
        pendingScrollTask?.cancel()

        guard let target = (practiceMilestones.first(where: { $0.isCurrent }) ?? practiceMilestones.first)?.id else {
            return
        }

        pendingScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let anchor = anchorPoint(for: target)
            if animated {
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(target, anchor: anchor)
                }
            } else {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }

    private func anchorPoint(for lessonId: Int) -> UnitPoint {
        lessonId <= 2 ? .top : UnitPoint(x: 0.5, y: 0.6)
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
        let sortedIdeas = (book.ideas ?? []).sortedByNumericId()
        var milestones: [PracticeMilestone] = []
        for info in lessonInfos {
            guard info.lessonNumber - 1 < sortedIdeas.count else { continue }
            let idea = sortedIdeas[info.lessonNumber - 1]
            let metrics = lessonMetrics(for: idea, bookId: bookId)
            let isCurrent = info.lessonNumber == currentLessonNumber && info.isUnlocked && !info.isCompleted
            print("DEBUG: Creating milestone - Lesson \(info.lessonNumber): \(info.title), Unlocked: \(info.isUnlocked), Completed: \(info.isCompleted), Current: \(isCurrent)")
            let milestone = PracticeMilestone(
                id: info.lessonNumber,
                title: info.title,
                isCompleted: info.isCompleted,
                isCurrent: isCurrent,
                isReviewPractice: false,
                clarityPercent: metrics.clarityPercent,
                brainCalories: metrics.brainCalories,
                idea: idea,
                isUnlocked: info.isUnlocked
            )
            milestones.append(milestone)
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
                        isCurrent: false,
                        isReviewPractice: true,
                        clarityPercent: nil,
                        brainCalories: 0,
                        idea: nil,
                        isUnlocked: true
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
                        isCurrent: true,
                        isReviewPractice: true,
                        clarityPercent: nil,
                        brainCalories: 0,
                        idea: nil,
                        isUnlocked: true
                    )
                )
                currentLessonNumber = nextId
            }
        }

        await MainActor.run {
            print("DEBUG: Setting practiceMilestones array with \(milestones.count) milestones")
            self.practiceMilestones = milestones
            print("DEBUG: practiceMilestones.count after setting: \(self.practiceMilestones.count)")
            
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

}

// MARK: - Supporting Views & Helpers
private struct LessonCardView: View {
    let milestone: PracticeMilestone
    let palette: PracticePalette
    let showConnector: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.connectorSpacing) {
            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)

            if showConnector {
                Rectangle()
                    .fill(palette.seed)
                    .frame(width: Layout.connectorWidth, height: Layout.connectorHeight)
                    .padding(.leading, Layout.indicatorColumnWidth / 2 - Layout.connectorWidth / 2)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch milestone.state {
        case .past:
            pastCard
        case .present:
            presentCard
        case .future:
            futureCard
        }
    }

    private var pastCard: some View {
        HStack(alignment: .center, spacing: Layout.cardSpacing) {
            indicatorCircle(icon: "checkmark")
                .frame(width: Layout.indicatorColumnWidth)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                lessonLabel(color: palette.primaryT40)
                Text(milestone.title)
                    .font(DS.Typography.bodyBold)
                    .foregroundColor(palette.primaryT30)
                    .multilineTextAlignment(.leading)

                metricsRow
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Layout.pastVerticalPadding)
    }

    private var presentCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.presentCornerRadius, style: .continuous)
                .fill(palette.seed.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.presentCornerRadius, style: .continuous)
                        .stroke(palette.seed, lineWidth: 1.5)
                )
                .shadow(color: palette.seed.opacity(0.25), radius: 12, x: 0, y: 10)

            HStack(alignment: .center, spacing: Layout.cardSpacing) {
                Circle()
                    .fill(palette.playButtonFill)
                    .frame(width: Layout.presentIndicatorDiameter, height: Layout.presentIndicatorDiameter)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(palette.background)
                    )
                    .frame(width: Layout.indicatorColumnWidth)

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    lessonLabel(color: palette.primaryT40)
                    Text(milestone.title)
                        .font(DS.Typography.bodyBold)
                        .foregroundColor(palette.primaryT30)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.presentHorizontalPadding)
            .padding(.vertical, Layout.presentVerticalPadding)
        }
    }

    private var futureCard: some View {
        HStack(alignment: .center, spacing: Layout.cardSpacing) {
            Circle()
                .fill(palette.seed.opacity(0.2))
                .frame(width: Layout.indicatorDiameter, height: Layout.indicatorDiameter)
                .overlay(
                    Text("\(milestone.id)")
                        .font(DS.Typography.bodyBold)
                        .foregroundColor(palette.primaryT30.opacity(0.33))
                )
                .frame(width: Layout.indicatorColumnWidth)

            Text(milestone.title)
                .font(DS.Typography.body)
                .foregroundColor(palette.primaryT30.opacity(0.33))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Layout.pastVerticalPadding)
    }

    @ViewBuilder
    private var metricsRow: some View {
        let hasClarity = (milestone.clarityPercent ?? 0) > 0
        let hasBcal = milestone.brainCalories > 0
        if hasClarity || hasBcal {
            HStack(spacing: Layout.metricsSpacing) {
                if let clarity = milestone.clarityPercent, clarity >= 0 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette.primaryT40)
                            .frame(width: 14, height: 14)
                            .blur(radius: blurRadius(for: clarity))
                        HStack(spacing: 2) {
                            Text("\(Int(clarity))%")
                                .font(DS.Typography.caption)
                                .fontWeight(.semibold)
                            Text("clarity")
                                .font(DS.Typography.caption)
                                .fontWeight(.regular)
                        }
                        .foregroundColor(palette.primaryT40)
                    }
                }

                if hasBcal {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(palette.primaryT40)
                        HStack(spacing: 2) {
                            Text("\(milestone.brainCalories)")
                                .font(DS.Typography.caption)
                                .fontWeight(.semibold)
                            Text("bCals burned")
                                .font(DS.Typography.caption)
                                .fontWeight(.regular)
                        }
                        .foregroundColor(palette.primaryT40)
                    }
                }
            }
        }
    }

    private func lessonLabel(color: Color) -> some View {
        Text("Lesson \(milestone.id)")
            .font(DS.Typography.caption)
            .foregroundColor(color)
    }

    private func indicatorCircle(icon: String) -> some View {
        Circle()
            .fill(palette.seed.opacity(0.2))
            .overlay(
                Circle()
                    .stroke(palette.seed, lineWidth: 1.5)
            )
            .frame(width: Layout.indicatorDiameter, height: Layout.indicatorDiameter)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.primaryT40)
            )
            .frame(width: Layout.indicatorColumnWidth)
    }

    private func blurRadius(for clarity: Double) -> CGFloat {
        let clamped = min(max(clarity, 0), 100)
        return CGFloat((100 - clamped) / 100.0) * Layout.clarityBlurMaxRadius
    }
}

enum LessonCardState {
    case past
    case present
    case future
}

private struct PracticePalette {
    let primaryT30: Color
    let primaryT40: Color
    let primaryT50: Color
    let primaryT70: Color
    let background: Color
    let flatBackground: Color
    let seed: Color
    let playButtonFill: Color

    init(roles: [PaletteRole], seedColor: Color?, tokens: ThemeTokens) {
        primaryT30 = roles.color(role: .primary, tone: 30) ?? tokens.onSurface
        primaryT40 = roles.color(role: .primary, tone: 40) ?? tokens.onSurface
        primaryT50 = roles.color(role: .primary, tone: 50) ?? tokens.onSurface
        primaryT70 = roles.color(role: .primary, tone: 70) ?? tokens.onSurface
        background = tokens.background
        flatBackground = roles.color(role: .primary, tone: 95)
            ?? roles.color(role: .neutral, tone: 95)
            ?? roles.color(role: .neutralVariant, tone: 95)
            ?? tokens.background
        seed = seedColor
            ?? roles.color(role: .primary, tone: 90)
            ?? tokens.primary
        let tertiary30 = roles.color(role: .tertiary, tone: 30)
        playButtonFill = tertiary30 ?? seed
    }
}

private struct LessonMetrics {
    let clarityPercent: Double?
    let brainCalories: Int
}

struct PracticeMilestone: Identifiable, Equatable {
    let id: Int
    let title: String
    var isCompleted: Bool
    var isCurrent: Bool
    let isReviewPractice: Bool
    let clarityPercent: Double?
    let brainCalories: Int
    let idea: Idea?
    let isUnlocked: Bool

    var state: LessonCardState {
        if isCurrent { return .present }
        return isCompleted ? .past : .future
    }

    static func == (lhs: PracticeMilestone, rhs: PracticeMilestone) -> Bool {
        lhs.id == rhs.id &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isReviewPractice == rhs.isReviewPractice
    }
}

private struct Layout {
    static let horizontalPadding: CGFloat = 28
    static let heroTopPadding: CGFloat = 8
    static let minimumSafeInset: CGFloat = 12
    static let safeInsetReduction: CGFloat = 24
    static let bottomPadding: CGFloat = 48
    static let sectionSpacing: CGFloat = 24
    static let headerSpacing: CGFloat = 16
    static let heroSpacing: CGFloat = 20
    static let timelineSpacing: CGFloat = 24
    static let timelineTopInset: CGFloat = 20
    static let coverSize = CGSize(width: 104, height: 160)
    static let headerBlurRadius: CGFloat = 20
    static let headerFadeHeight: CGFloat = 60
    static let headerBottomBorderWidth: CGFloat = 0.5
    static let initialStickyHeaderHeight: CGFloat = 320
    static let clarityBlurMaxRadius: CGFloat = 10
    static let indicatorDiameter: CGFloat = 48
    static let presentIndicatorDiameter: CGFloat = 56
    static let indicatorColumnWidth: CGFloat = 60
    static let cardSpacing: CGFloat = 16
    static let connectorHeight: CGFloat = 16
    static let connectorWidth: CGFloat = 2
    static let connectorSpacing: CGFloat = 6
    static let metricsSpacing: CGFloat = 20
    static let presentCornerRadius: CGFloat = 36
    static let presentHorizontalPadding: CGFloat = 20
    static let presentVerticalPadding: CGFloat = 18
    static let pastVerticalPadding: CGFloat = 8
    static let titleAuthorSpacing: CGFloat = 4
}

private struct StickyHeaderHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = Layout.initialStickyHeaderHeight
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum AmazonLinkBuilder {
    static func url(for book: Book) -> URL? {
        let region = Locale.current.region?.identifier ?? "US"
        let domain = domain(for: region)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.amazon\(domain)"
        components.path = "/s"
        let query = [book.title, book.author].compactMap { $0 }.joined(separator: " ")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        components.queryItems = [
            URLQueryItem(name: "k", value: trimmed),
            URLQueryItem(name: "i", value: "stripbooks-intl-ship")
        ]
        return components.url
    }

    private static func domain(for region: String) -> String {
        switch region.uppercased() {
        case "CA": return ".ca"
        case "GB", "UK": return ".co.uk"
        case "AU": return ".com.au"
        case "IN": return ".in"
        case "FR": return ".fr"
        case "DE": return ".de"
        case "ES": return ".es"
        case "IT": return ".it"
        case "JP": return ".co.jp"
        case "BR": return ".com.br"
        case "MX": return ".com.mx"
        case "NL": return ".nl"
        case "SE": return ".se"
        case "AE": return ".ae"
        case "SG": return ".sg"
        default: return ".com"
        }
    }
}

enum PracticeType {
    case quick
    case focused
    case review
}
