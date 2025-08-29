import SwiftUI
import SwiftData

struct DailyPracticeHomepage: View {
    let book: Book
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var practiceStats: PracticeStats?
    @State private var currentLessonNumber: Int = 0
    @State private var selectedLesson: GeneratedLesson? = nil
    
    // Real lessons generated from book ideas
    @State private var practiceMilestones: [PracticeMilestone] = []
    @State private var generatedLessons: [GeneratedLesson] = []
    
    private var lessonStorage: LessonStorageService {
        LessonStorageService(modelContext: modelContext)
    }
    
    private var lessonGenerator: LessonGenerationService {
        LessonGenerationService(
            modelContext: modelContext,
            openAIService: openAIService
        )
    }
    
    private var masteryService: MasteryService {
        MasteryService(modelContext: modelContext)
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
            .navigationTitle("Practice Session")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadPracticeData()
            }
            .fullScreenCover(item: $selectedLesson) { lesson in
                DailyPracticeView(
                    book: book,
                    openAIService: openAIService,
                    practiceType: .quick,
                    selectedLesson: lesson,
                    onPracticeComplete: {
                        // Mark lesson as completed and unlock next lesson
                        completeLesson(lesson)
                        // Dismiss after completion
                        selectedLesson = nil
                    }
                )
                .onAppear {
                    print("DEBUG: Presenting DailyPracticeView with lesson \(lesson.lessonNumber)")
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
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
                                            let sortedIdeas = book.ideas.sorted { idea1, idea2 in
                                                let id1 = idea1.id.split(separator: "i")
                                                let id2 = idea2.id.split(separator: "i")
                                                let num1 = id1.count > 1 ? Int(id1[1]) ?? 0 : 0
                                                let num2 = id2.count > 1 ? Int(id2[1]) ?? 0 : 0
                                                return num1 < num2
                                            }
                                            
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
                    if let currentMilestone = practiceMilestones.first(where: { $0.isCurrent }) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(currentMilestone.id, anchor: .top)
                        }
                    }
                }
            }
        }
            }
    }
    
    
    // MARK: - Lesson Management
    private func completeLesson(_ lesson: GeneratedLesson) {
        print("DEBUG: Completing lesson \(lesson.lessonNumber)")
        
        // Update the milestone for this lesson
        if let milestoneIndex = practiceMilestones.firstIndex(where: { $0.id == lesson.lessonNumber }) {
            practiceMilestones[milestoneIndex].isCompleted = true
            practiceMilestones[milestoneIndex].isCurrent = false
            
            print("DEBUG: Marked lesson \(lesson.lessonNumber) as completed")
            
            // Move to next milestone if available
            if milestoneIndex + 1 < practiceMilestones.count {
                practiceMilestones[milestoneIndex + 1].isCurrent = true
                print("DEBUG: Unlocked lesson \(practiceMilestones[milestoneIndex + 1].id)")
            } else {
                print("DEBUG: All lessons completed!")
            }
            
            // Mark the idea as mastered if lesson is completed
            if let idea = book.ideas.first(where: { $0.id == lesson.primaryIdeaId }) {
                print("DEBUG: Marking idea \(idea.title) as progressed")
            }
        }
        
        // Reload practice data to refresh stats and milestones
        Task {
            await loadPracticeData()
        }
    }
    
    // MARK: - Data Loading
    private func loadPracticeData() async {
        let bookId = book.id.uuidString
        
        // Get lesson info for display (no actual generation yet)
        let lessonInfos = lessonStorage.getAllLessonInfo(book: book)
        let currentLessonNumber = lessonStorage.getCurrentLessonNumber(bookId: bookId)
        
        print("DEBUG: Current lesson number: \(currentLessonNumber)")
        print("DEBUG: Retrieved \(lessonInfos.count) lesson infos from LessonStorage")
        
        // Convert to milestones for UI
        let milestones = lessonInfos.enumerated().map { index, info in
            print("DEBUG: Creating milestone - Lesson \(info.lessonNumber): \(info.title), Unlocked: \(info.isUnlocked), Completed: \(info.isCompleted)")
            return PracticeMilestone(
                id: info.lessonNumber,
                title: info.title,
                isCompleted: info.isCompleted,
                isCurrent: info.lessonNumber == currentLessonNumber && info.isUnlocked
            )
        }
        
        // Calculate practice stats
        let ideas = book.ideas
        
        var newIdeasCount = 0
        var reviewDueCount = 0
        var masteredCount = 0
        
        for idea in ideas {
            let mastery = masteryService.getMastery(for: idea.id, bookId: bookId)
            
            if mastery.masteryPercentage == 0 {
                newIdeasCount += 1
            } else if mastery.isFullyMastered {
                masteredCount += 1
                
                // Check if review is due
                if let reviewData = mastery.reviewStateData,
                   let reviewState = try? JSONDecoder().decode(FSRSScheduler.ReviewState.self, from: reviewData),
                   FSRSScheduler.isReviewDue(reviewState: reviewState) {
                    reviewDueCount += 1
                }
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
        .disabled(!milestone.isCurrent)
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