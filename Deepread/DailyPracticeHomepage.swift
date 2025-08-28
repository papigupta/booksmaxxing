import SwiftUI
import SwiftData

struct DailyPracticeHomepage: View {
    let book: Book
    let openAIService: OpenAIService
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var practiceStats: PracticeStats?
    @State private var showingPractice = false
    
    // Practice milestones for linear path
    @State private var practiceMilestones: [PracticeMilestone] = [
        PracticeMilestone(id: 1, title: "Foundation Basics", isCompleted: true, isCurrent: false),
        PracticeMilestone(id: 2, title: "Core Concepts", isCompleted: true, isCurrent: false),
        PracticeMilestone(id: 3, title: "Key Principles", isCompleted: true, isCurrent: false),
        PracticeMilestone(id: 4, title: "Today's Focus", isCompleted: false, isCurrent: true),
        PracticeMilestone(id: 5, title: "Advanced Ideas", isCompleted: false, isCurrent: false),
        PracticeMilestone(id: 6, title: "Deep Connections", isCompleted: false, isCurrent: false),
        PracticeMilestone(id: 7, title: "Integration", isCompleted: false, isCurrent: false),
        PracticeMilestone(id: 8, title: "Application", isCompleted: false, isCurrent: false),
        PracticeMilestone(id: 9, title: "Mastery Check", isCompleted: false, isCurrent: false),
        PracticeMilestone(id: 10, title: "Expert Level", isCompleted: false, isCurrent: false),
    ]
    
    private var practiceGenerator: PracticeGenerator {
        PracticeGenerator(
            modelContext: modelContext,
            openAIService: openAIService
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(DS.Colors.secondaryText)
                }
            }
            .task {
                await loadPracticeStats()
            }
            .fullScreenCover(isPresented: $showingPractice) {
                DailyPracticeView(
                    book: book,
                    openAIService: openAIService,
                    practiceType: .quick,
                    onPracticeComplete: {
                        // Advance milestone when practice is completed
                        advanceMilestone()
                    }
                )
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
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.lg) {
                        ForEach(Array(practiceMilestones.enumerated()), id: \.element.id) { index, milestone in
                            VStack(spacing: DS.Spacing.sm) {
                                MilestoneNode(
                                    milestone: milestone,
                                    onTap: {
                                        if milestone.isCurrent {
                                            print("DEBUG: Starting practice session")
                                            showingPractice = true
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
    
    
    // MARK: - Milestone Management
    private func advanceMilestone() {
        // Find current milestone and mark as completed
        if let currentIndex = practiceMilestones.firstIndex(where: { $0.isCurrent }) {
            practiceMilestones[currentIndex].isCompleted = true
            practiceMilestones[currentIndex].isCurrent = false
            
            // Move to next milestone if available
            if currentIndex + 1 < practiceMilestones.count {
                practiceMilestones[currentIndex + 1].isCurrent = true
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadPracticeStats() async {
        // Analyze the book's ideas to generate stats
        let ideas = book.ideas
        
        let newIdeas = ideas.filter { $0.masteryLevel == 0 }
        let masteredIdeas = ideas.filter { $0.masteryLevel >= 3 }
        
        // Check for review due items
        let spacedRepetitionService = SpacedRepetitionService(modelContext: modelContext)
        let reviewDueIdeas = spacedRepetitionService.getIdeasNeedingReview().filter { idea in
            ideas.contains { $0.id == idea.id }
        }
        
        await MainActor.run {
            self.practiceStats = PracticeStats(
                newIdeasCount: newIdeas.count,
                reviewDueCount: reviewDueIdeas.count,
                masteredCount: masteredIdeas.count
            )
            
            print("DEBUG: Loaded practice stats - New: \(newIdeas.count), Review: \(reviewDueIdeas.count), Mastered: \(masteredIdeas.count)")
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