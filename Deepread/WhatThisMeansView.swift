import SwiftUI

struct WhatThisMeansView: View {
    let idea: Idea
    let evaluationResult: EvaluationResult
    let userResponse: String
    let level: Int
    let openAIService: OpenAIService
    
    @State private var showingNextLevel = false
    @State private var showingCelebration = false
    @State private var nextLevel: Int = 0
    @State private var navigateToHome = false
    @State private var showingPrimer = false // Add this line
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Book title - subtle at top
                Text(idea.bookTitle)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                // Idea title
                Text(idea.title)
                    .font(DS.Typography.title)
                    .foregroundColor(DS.Colors.primaryText)
                
                // Level Progression Explanation
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("What This Means")
                        .font(DS.Typography.headline)
                        .foregroundColor(DS.Colors.primaryText)
                    
                    let progressionInfo = getLevelProgressionInfo(starScore: evaluationResult.starScore, currentLevel: level)
                    
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(progressionInfo.explanation)
                            .font(DS.Typography.body)
                            .foregroundColor(DS.Colors.primaryText)
                        
                        HStack(spacing: DS.Spacing.xs) {
                            DSIcon("arrow.right.circle.fill", size: 24)
                            
                            Text("Next: \(progressionInfo.nextLevelName)")
                                .font(DS.Typography.headline)
                                .foregroundColor(DS.Colors.primaryText)
                        }
                        .padding(.top, DS.Spacing.xxs)
                    }
                    .dsCard(padding: DS.Spacing.md, borderColor: DS.Colors.border, backgroundColor: DS.Colors.secondaryBackground)
                }
                
                // Continue Button
                Button(getButtonText(starScore: evaluationResult.starScore, currentLevel: level)) {
                    let nextLevelResult = determineNextLevel(starScore: evaluationResult.starScore, currentLevel: level)
                    
                    if nextLevelResult == -1 {
                        // Mastery achieved - show celebration
                        showingCelebration = true
                    } else {
                        // Continue to next level
                        nextLevel = nextLevelResult
                        saveNextLevel(nextLevel: nextLevelResult)
                        showingNextLevel = true
                    }
                }
                .dsPrimaryButton()
                .padding(.top, DS.Spacing.md)
                
                // Primer suggestion for low scores
                if evaluationResult.starScore == 1 {
                    VStack(spacing: DS.Spacing.xs) {
                        Text("Need a refresher?")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        
                        Button(action: {
                            showingPrimer = true
                        }) {
                            HStack {
                                DSIcon("lightbulb", size: 16)
                                Text("View Primer")
                                    .font(DS.Typography.body)
                            }
                            .foregroundColor(DS.Colors.primaryText)
                        }
                        .dsSmallButton()
                    }
                    .padding(.top, DS.Spacing.xs)
                }
                
                Spacer(minLength: DS.Spacing.xl)
            }
            .padding(.horizontal, DS.Spacing.md + DS.Spacing.xxs) // 20pt equivalent
            .padding(.top, DS.Spacing.md)
        }
        .navigationTitle("What This Means")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Hide the back button
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    navigateToHome = true
                }) {
                    DSIcon("text.book.closed", size: 18)
                }
                .accessibilityLabel("Go to home")
                .accessibilityHint("Return to all extracted ideas")
            }
        }
        .navigationDestination(isPresented: $showingNextLevel) {
            // Start new learning loop
            LevelLoadingView(idea: idea, level: nextLevel, openAIService: openAIService)
        }
        .navigationDestination(isPresented: $showingCelebration) {
            // Show celebration screen
            CelebrationView(
                idea: idea,
                userResponse: userResponse,
                level: level,
                starScore: evaluationResult.starScore,
                openAIService: openAIService
            )
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: openAIService)
        }
    }
    
    // MARK: - Progress Saving
    
    private func saveNextLevel(nextLevel: Int) {
        idea.currentLevel = nextLevel
        do {
            try modelContext.save()
            print("DEBUG: Saved next level to \(nextLevel) for idea: \(idea.title)")
        } catch {
            print("DEBUG: Failed to save next level: \(error)")
        }
    }
    
    
    // MARK: - Level Progression Logic
    
    private func getLevelProgressionInfo(starScore: Int, currentLevel: Int) -> (explanation: String, nextLevelName: String) {
        switch currentLevel {
        case 1: // Why Care
            return getWhyCareProgression(starScore: starScore)
        case 2: // When Use  
            return getWhenUseProgression(starScore: starScore)
        case 3: // How Wield
            return getHowWieldProgression(starScore: starScore)
        default:
            return getDefaultProgression(starScore: starScore, currentLevel: currentLevel)
        }
    }
    
    private func determineNextLevel(starScore: Int, currentLevel: Int) -> Int {
        switch currentLevel {
        case 1: // Why Care
            switch starScore {
            case 1: return 1 // ⭐ Retry Level 1
            case 2: return 2 // ⭐⭐ Advance to Level 2  
            case 3: return 3 // ⭐⭐⭐ Skip to Level 3
            default: return 1
            }
        case 2: // When Use
            switch starScore {
            case 1: return 2 // ⭐ Retry Level 2
            case 2, 3: return 3 // ⭐⭐ or ⭐⭐⭐ Advance to Level 3
            default: return 2
            }
        case 3: // How Wield  
            switch starScore {
            case 1: return 3 // ⭐ Retry Level 3
            case 2, 3: return -1 // ⭐⭐ or ⭐⭐⭐ Mastery achieved!
            default: return 3
            }
        default:
            return currentLevel + 1
        }
    }
    
    private func getWhyCareProgression(starScore: Int) -> (explanation: String, nextLevelName: String) {
        switch starScore {
        case 1: // ⭐ Getting There
            return (
                explanation: "Your understanding of why this idea matters is developing. Let's explore it again to build deeper insight.",
                nextLevelName: "Level 1: Why Care (Retry)"
            )
        case 2: // ⭐⭐ Solid Grasp  
            return (
                explanation: "Great work! You understand the significance well. Ready to learn when to use this idea.",
                nextLevelName: "Level 2: When Use"
            )
        case 3: // ⭐⭐⭐ Aha! Moment
            return (
                explanation: "Incredible insight! You've achieved deep understanding. Let's jump to the highest level - wielding this idea creatively.",
                nextLevelName: "Level 3: How Wield"
            )
        default:
            return (
                explanation: "Let's continue building your understanding.",
                nextLevelName: "Level 1: Why Care (Retry)"
            )
        }
    }
    
    private func getWhenUseProgression(starScore: Int) -> (explanation: String, nextLevelName: String) {
        switch starScore {
        case 1: // ⭐ Getting There
            return (
                explanation: "Recognition skills need more work. Let's practice identifying when to use this idea.",
                nextLevelName: "Level 2: When Use (Retry)"
            )
        case 2: // ⭐⭐ Solid Grasp
            return (
                explanation: "Excellent recognition! You know when to apply this idea. Ready for creative mastery.",
                nextLevelName: "Level 3: How Wield"
            )
        case 3: // ⭐⭐⭐ Aha! Moment
            return (
                explanation: "Perfect application sense! You've mastered recognition. Time for creative wielding.",
                nextLevelName: "Level 3: How Wield"
            )
        default:
            return (
                explanation: "Continue developing your recognition skills.",
                nextLevelName: "Level 2: When Use (Retry)"
            )
        }
    }
    
    private func getHowWieldProgression(starScore: Int) -> (explanation: String, nextLevelName: String) {
        switch starScore {
        case 1: // ⭐ Getting There
            return (
                explanation: "Creative mastery is the hardest level. Let's keep practicing how to wield this idea innovatively.",
                nextLevelName: "Level 3: How Wield (Retry)"
            )
        case 2: // ⭐⭐ Solid Grasp
            return (
                explanation: "Excellent creative work! You've mastered this idea completely. Congratulations!",
                nextLevelName: "Mastery Achieved! 🎉"
            )
        case 3: // ⭐⭐⭐ Aha! Moment
            return (
                explanation: "Incredible mastery! You've achieved the highest level of understanding and creative insight. You're now an expert!",
                nextLevelName: "Master Level Achieved! ✨"
            )
        default:
            return (
                explanation: "Continue developing your creative mastery.",
                nextLevelName: "Level 3: How Wield (Retry)"
            )
        }
    }
    
    private func getDefaultProgression(starScore: Int, currentLevel: Int) -> (explanation: String, nextLevelName: String) {
        return (
            explanation: "You've completed this level. Continue your learning journey.",
            nextLevelName: "Level \(currentLevel + 1)"
        )
    }
    
    private func getButtonText(starScore: Int, currentLevel: Int) -> String {
        let nextLevel = determineNextLevel(starScore: starScore, currentLevel: currentLevel)
        
        if nextLevel == -1 {
            return starScore == 3 ? "🎉 Celebrate Mastery!" : "🎉 Mastery Achieved!"
        } else if nextLevel == currentLevel {
            return "Try Again"
        } else {
            return "Continue Learning Journey"
        }
    }
}

#Preview {
    NavigationStack {
        WhatThisMeansView(
            idea: Idea(
                id: "i1",
                title: "Norman Doors",
                description: "The mind fills in blanks. But what if the blanks are the most important part?",
                bookTitle: "The Design of Everyday Things",
                depthTarget: 2,
                masteryLevel: 0,
                lastPracticed: nil,
                currentLevel: nil
            ),
            evaluationResult: EvaluationResult(
                level: "L1",
                starScore: 2,
                starDescription: "Solid Grasp",
                pass: true,
                insightCompass: WisdomFeedback(
                    wisdomOpening: "Your understanding shows clear connection to the core concept.",
                    rootCause: "You've identified the key principle behind Norman doors.",
                    missingFoundation: "Consider exploring more examples to deepen understanding.",
                    elevatedPerspective: "Think about how this applies to digital interfaces too.",
                    nextLevelPrep: "Ready to explore when and where to apply this concept.",
                    personalizedWisdom: "Your design background gives you unique insight here."
                ),
                idealAnswer: "Norman doors reveal a fundamental design principle: when an object's design suggests one action but requires another, confusion is inevitable. This matters because these design failures create cognitive friction in our daily lives. Every time we encounter a door that looks pushable but needs to be pulled, we experience a micro-failure of intuitive design. This principle extends beyond doors to all interfaces - digital buttons that don't look clickable, forms that hide required fields, or navigation that misleads users. The significance lies in recognizing that good design should guide behavior naturally, eliminating the need for instructions or trial-and-error.",
                keyGap: "You missed the broader design principle - it's not just about doors, but about how design communicates intended actions to users.",
                hasRealityCheck: true,
                mastery: false
            ),
            userResponse: "This is my response about Norman Doors...",
            level: 1,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 