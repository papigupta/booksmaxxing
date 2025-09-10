import SwiftUI
import SwiftData

struct DailyPracticeHomepage: View {
    let book: Book
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var streakManager: StreakManager
    
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
        NavigationStack {
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
            .task {
                await loadPracticeData()
            }
            .onAppear {
                // Reload data when view appears (e.g., returning from lesson)
                Task {
                    await loadPracticeData()
                }
            }
            .onChange(of: refreshID) { _, newValue in
                // Force reload when refresh is triggered
                Task {
                    await loadPracticeData()
                }
            }
            .fullScreenCover(item: $selectedLesson) { lesson in
                // Check if this is a special review session
                if lesson.lessonNumber == -1 {
                    // Use the new review-enabled practice view
                    DailyPracticeWithReviewView(
                        book: book,
                        openAIService: openAIService,
                        onPracticeComplete: {
                            print("DEBUG: ✅✅ Review practice complete")
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Top row: back button • streak • debug menu
            HStack {
                // Back to Book Button
                Button(action: { dismiss() }) {
                    HStack(spacing: DS.Spacing.xs) {
                        DSIcon("book.fill", size: 16)
                        Text("Back to Book")
                            .font(DS.Typography.caption)
                    }
                }
                .dsSmallButton()

                Spacer()

                // Streak indicator on homepage
                StreakIndicatorView()

                // Tiny overflow menu for debug/review shortcuts
                Menu {
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
                        }) {
                            Label("Review Practice\(reviewQueueCount.map { " (\($0))" } ?? "")", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    if DebugFlags.enableDevControls {
                        Button(action: {
                            let bookId = book.id.uuidString
                            curveballService.forceAllCurveballsDue(bookId: bookId, bookTitle: book.title)
                            refreshView()
                        }) {
                            Label("Force Curveball Due", systemImage: "bolt.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DS.Colors.primaryText)
                        .padding(.leading, DS.Spacing.sm)
                }
                .contentShape(Rectangle())
            }
            .padding(.bottom, DS.Spacing.sm)
            
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Ready to practice?")
                        .font(DS.Typography.largeTitle)
                        .foregroundColor(DS.Colors.primaryText)
                    
                    Text(book.title)
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Colors.secondaryText)
                }
                
                Spacer()
                
                // Book cover thumbnail
                if book.coverImageUrl != nil || book.thumbnailUrl != nil {
                    BookCoverView(
                        thumbnailUrl: book.thumbnailUrl,
                        coverUrl: book.coverImageUrl,
                        isLargeView: false
                    )
                    .frame(width: 60, height: 90)
                    .cornerRadius(6)
                }
            }
        }
    }
    
    // MARK: - Stats Section
    private func statsSection(_ stats: PracticeStats) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Your Progress")
                .font(DS.Typography.headline)
                .foregroundColor(DS.Colors.primaryText)
            
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
        .background(DS.Colors.secondaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - Practice Path Section
    private var practicePathSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Your Learning Path")
                .font(DS.Typography.headline)
                .foregroundColor(DS.Colors.primaryText)
            
            if practiceMilestones.isEmpty {
                Text("Loading lessons...")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.secondaryText)
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
                                        
                                        // Allow tapping on unlocked lessons
                                        let bookId = book.id.uuidString
                                        guard let lessonInfo = lessonStorage.getLessonInfo(bookId: bookId, lessonNumber: milestone.id, book: book) else {
                                            print("ERROR: Could not get lesson info for lesson \(milestone.id)")
                                            return
                                        }
                                        
                                        if lessonInfo.isUnlocked {
                                            
                                            print("DEBUG: Starting lesson generation for lesson \(milestone.id)")
                                            
                                            // Create a temporary GeneratedLesson for compatibility
                                            let emptyMistakeCorrections: [(ideaId: String, concepts: [String])] = []
                                            
                                            // Get the actual idea for this lesson to set primaryIdeaId
                                            let sortedIdeas = book.ideas.sortedByNumericId()
                                            
                                            let primaryIdeaId: String
                                            if milestone.id > 0 && milestone.id <= sortedIdeas.count {
                                                primaryIdeaId = sortedIdeas[milestone.id - 1].id
                                            } else {
                                                print("ERROR: Could not find idea for lesson \(milestone.id)")
                                                primaryIdeaId = sortedIdeas.first?.id ?? "unknown"
                                            }
                                            
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
                                            
                                            print("DEBUG: Created temp lesson with primaryIdeaId: \(primaryIdeaId)")
                                            
                                            // Set the lesson to trigger the fullScreenCover
                                            selectedLesson = tempLesson
                                        } else {
                                            print("DEBUG: Lesson \(milestone.id) is not unlocked or not found")
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
        // Ensure any due curveballs are queued for this book before computing stats
        curveballService.ensureCurveballsQueuedIfDue(bookId: bookId, bookTitle: book.title)
        
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
        let milestones = lessonInfos.enumerated().map { index, info in
            let isCurrent = info.lessonNumber == currentLessonNumber && info.isUnlocked && !info.isCompleted
            print("DEBUG: Creating milestone - Lesson \(info.lessonNumber): \(info.title), Unlocked: \(info.isUnlocked), Completed: \(info.isCompleted), Current: \(isCurrent)")
            return PracticeMilestone(
                id: info.lessonNumber,
                title: info.title,
                isCompleted: info.isCompleted,
                isCurrent: isCurrent
            )
        }
        
        // Load review queue stats for this specific book (after ensuring curveballs queued)
        let queueStats = reviewQueueManager.getQueueStatistics(bookId: book.id.uuidString)
        let totalReviewItems = queueStats.totalMCQs + queueStats.totalOpenEnded
        
        // Calculate practice stats
        let ideas = book.ideas
        
        var newIdeasCount = 0
        let reviewDueCount = totalReviewItems  // Use actual queue count
        var masteredCount = 0
        
        for idea in ideas {
            let coverage = coverageService.getCoverage(for: idea.id, bookId: bookId)
            
            if coverage.coveragePercentage == 0 {
                newIdeasCount += 1
            } else if coverage.isFullyCovered {
                masteredCount += 1
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
}

// MARK: - Supporting Views
private struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DS.Colors.black)
            
            Text(value)
                .font(DS.Typography.headline)
                .foregroundColor(DS.Colors.primaryText)
            
            Text(title)
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)
            
            Text(subtitle)
                .font(DS.Typography.small)
                .foregroundColor(DS.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.sm)
        .background(DS.Colors.primaryBackground)
        .cornerRadius(6)
    }
}

private struct MilestoneNode: View {
    let milestone: PracticeMilestone
    let lesson: GeneratedLesson?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                // Milestone circle
                ZStack {
                    Circle()
                        .fill(circleColor)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(strokeColor, lineWidth: milestone.isCurrent ? 3 : 1)
                        )
                        .scaleEffect(milestone.isCurrent ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: milestone.isCurrent)
                    
                    // Icon or lesson number
                    if milestone.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    } else if milestone.isCurrent {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(milestone.id)")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(DS.Colors.gray500)
                    }
                }
                
                // Lesson info
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Lesson \(milestone.id)")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                    
                    Text(milestone.title)
                        .font(DS.Typography.bodyBold)
                        .foregroundColor(milestone.isCurrent ? DS.Colors.black : (milestone.isCompleted ? DS.Colors.black : DS.Colors.gray500))
                }
                
                Spacer()
                
                // Status indicator
                if milestone.isCurrent {
                    Text("START")
                        .font(DS.Typography.small)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Colors.black)
                        .cornerRadius(12)
                }
            }
            .padding(DS.Spacing.md)
            .background(milestone.isCurrent ? DS.Colors.black.opacity(0.05) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(milestone.isCurrent ? DS.Colors.black.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!milestone.isCompleted && !milestone.isCurrent)
    }
    
    private var circleColor: Color {
        if milestone.isCompleted {
            return Color.green
        } else if milestone.isCurrent {
            return DS.Colors.black
        } else {
            return DS.Colors.gray200
        }
    }
    
    private var strokeColor: Color {
        if milestone.isCompleted {
            return Color.green.opacity(0.3)
        } else if milestone.isCurrent {
            return DS.Colors.black
        } else {
            return DS.Colors.gray300
        }
    }
}

// MARK: - Data Models
struct PracticeStats {
    let newIdeasCount: Int
    let reviewDueCount: Int
    let masteredCount: Int
}

struct PracticeMilestone {
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
