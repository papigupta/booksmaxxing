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
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Book title - subtle at top
                Text(idea.bookTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                // Idea title
                Text(idea.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                // Level Progression Explanation
                VStack(alignment: .leading, spacing: 12) {
                    Text("What This Means")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    let progressionInfo = getLevelProgressionInfo(score: evaluationResult.score10, currentLevel: level)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(progressionInfo.explanation)
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            
                            Text("Next: \(progressionInfo.nextLevelName)")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.blue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                
                // Continue Button
                Button(getButtonText(score: evaluationResult.score10, currentLevel: level)) {
                    let nextLevelResult = determineNextLevel(score: evaluationResult.score10, currentLevel: level)
                    
                    // Save intermediate progress before proceeding
                    saveProgress(score: evaluationResult.score10, currentLevel: level)
                    
                    if nextLevelResult == -1 {
                        // Mastery achieved - show celebration
                        showingCelebration = true
                    } else {
                        // Continue to next level
                        nextLevel = nextLevelResult
                        showingNextLevel = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 16)
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .navigationTitle("What This Means")
        .navigationBarTitleDisplayMode(.inline)
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
                score: evaluationResult.score10,
                openAIService: openAIService
            )
        }
    }
    
    // MARK: - Progress Saving
    
    private func saveProgress(score: Int, currentLevel: Int) {
        // Update mastery level based on current progress
        let newMasteryLevel = calculateMasteryLevel(score: score, currentLevel: currentLevel)
        
        // Only update if the new level is higher than current
        if newMasteryLevel > idea.masteryLevel {
            idea.masteryLevel = newMasteryLevel
            idea.lastPracticed = Date()
            
            // Save to database immediately
            do {
                try modelContext.save()
                print("DEBUG: Saved intermediate progress - mastery level updated to \(newMasteryLevel) for idea: \(idea.title)")
            } catch {
                print("DEBUG: Failed to save intermediate progress: \(error)")
            }
        }
    }
    
    private func calculateMasteryLevel(score: Int, currentLevel: Int) -> Int {
        // Calculate mastery level based on current level and score
        switch currentLevel {
        case 0: // Thought Dump
            switch score {
            case 1...4: return 1 // Basic understanding
            case 5...7: return 2 // Intermediate understanding
            case 8...10: return 2 // Intermediate understanding, ready for advanced
            default: return 1
            }
        case 1: // Use
            switch score {
            case 1...4: return 1 // Still basic
            case 5...7: return 2 // Intermediate understanding
            case 8...10: return 2 // Intermediate understanding, ready for advanced
            default: return 2
            }
        case 2: // Think with
            switch score {
            case 1...4: return 2 // Still intermediate
            case 5...7: return 2 // Intermediate understanding
            case 8...10: return 2 // Intermediate understanding, ready for mastery
            default: return 2
            }
        case 3: // Build with
            switch score {
            case 1...4: return 2 // Still intermediate
            case 5...7: return 2 // Intermediate understanding
            case 8...10: return 3 // Mastery achieved
            default: return 2
            }
        default:
            return idea.masteryLevel // Keep current level
        }
    }
    
    // MARK: - Level Progression Logic
    
    private func getLevelProgressionInfo(score: Int, currentLevel: Int) -> (explanation: String, nextLevelName: String) {
        switch currentLevel {
        case 0: // Thought Dump
            return getThoughtDumpProgression(score: score)
        case 1: // Use
            return getUseLevelProgression(score: score)
        case 2: // Think with
            return getThinkWithProgression(score: score)
        case 3: // Build with
            return getBuildWithProgression(score: score)
        default:
            return getDefaultProgression(score: score, currentLevel: currentLevel)
        }
    }
    
    private func determineNextLevel(score: Int, currentLevel: Int) -> Int {
        switch currentLevel {
        case 0: // Thought Dump
            switch score {
            case 1...4: return 1 // Level 1: Use
            case 5...7: return 2 // Level 2: Think With
            case 8...10: return 3 // Level 3: Build With
            default: return 1
            }
        case 1: // Use
            switch score {
            case 1...4: return 1 // Retry Level 1
            case 5...7: return 2 // Level 2: Think With
            case 8...10: return 3 // Level 3: Build With
            default: return 2
            }
        case 2: // Think with
            switch score {
            case 1...4: return 2 // Retry Level 2
            case 5...7, 8...10: return 3 // Level 3: Build With
            default: return 3
            }
        case 3: // Build with
            switch score {
            case 1...4: return 3 // Retry Level 3
            case 5...7: return 3 // Retry Level 3 for improvement
            case 8...10: return -1 // Mastery achieved - show celebration
            default: return 3
            }
        default:
            return currentLevel + 1
        }
    }
    
    private func getThoughtDumpProgression(score: Int) -> (explanation: String, nextLevelName: String) {
        switch score {
        case 1...4:
            return (
                explanation: "Your understanding is still developing. Let's build a stronger foundation with practical applications.",
                nextLevelName: "Level 1: Use"
            )
        case 5...7:
            return (
                explanation: "Strong thinking! You've shown good engagement. Let's skip ahead to more advanced analysis.",
                nextLevelName: "Level 2: Think With"
            )
        case 8...10:
            return (
                explanation: "Exceptional depth! You're ready for the most challenging level of creative synthesis.",
                nextLevelName: "Level 3: Build With"
            )
        default:
            return (
                explanation: "Let's continue your learning journey.",
                nextLevelName: "Level 1: Use"
            )
        }
    }
    
    private func getUseLevelProgression(score: Int) -> (explanation: String, nextLevelName: String) {
        switch score {
        case 1...4:
            return (
                explanation: "Keep practicing practical applications. Mastery comes with repetition.",
                nextLevelName: "Level 1: Use (Retry)"
            )
        case 5...7:
            return (
                explanation: "Good application skills! Ready to use this idea as a thinking tool.",
                nextLevelName: "Level 2: Think With"
            )
        case 8...10:
            return (
                explanation: "Excellent application! You're ready to build new concepts with this idea.",
                nextLevelName: "Level 3: Build With"
            )
        default:
            return (
                explanation: "Continue developing your application skills.",
                nextLevelName: "Level 2: Think With"
            )
        }
    }
    
    private func getThinkWithProgression(score: Int) -> (explanation: String, nextLevelName: String) {
        switch score {
        case 1...4:
            return (
                explanation: "Critical thinking takes practice. Let's strengthen your analytical skills.",
                nextLevelName: "Level 2: Think With (Retry)"
            )
        case 5...7:
            return (
                explanation: "Solid analytical thinking! Ready to create new concepts.",
                nextLevelName: "Level 3: Build With"
            )
        case 8...10:
            return (
                explanation: "Outstanding critical thinking! You've mastered this level.",
                nextLevelName: "Level 3: Build With"
            )
        default:
            return (
                explanation: "Continue developing your critical thinking skills.",
                nextLevelName: "Level 3: Build With"
            )
        }
    }
    
    private func getBuildWithProgression(score: Int) -> (explanation: String, nextLevelName: String) {
        switch score {
        case 1...4:
            return (
                explanation: "Creative synthesis is challenging. Keep exploring and building.",
                nextLevelName: "Level 3: Build With (Retry)"
            )
        case 5...7:
            return (
                explanation: "Great creative work! You're developing strong synthesis skills.",
                nextLevelName: "Level 3: Build With (Retry)"
            )
        case 8...10:
            return (
                explanation: "Masterful synthesis! You've reached the highest level of understanding.",
                nextLevelName: "Mastery Achieved"
            )
        default:
            return (
                explanation: "Continue your creative journey.",
                nextLevelName: "Level 3: Build With (Retry)"
            )
        }
    }
    
    private func getDefaultProgression(score: Int, currentLevel: Int) -> (explanation: String, nextLevelName: String) {
        return (
            explanation: "You've completed this level. Continue your learning journey.",
            nextLevelName: "Level \(currentLevel + 1)"
        )
    }
    
    private func getButtonText(score: Int, currentLevel: Int) -> String {
        if currentLevel == 3 && score >= 8 {
            return "Celebrate Mastery"
        } else {
            return "Continue to Next Level"
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
                lastPracticed: nil
            ),
            evaluationResult: EvaluationResult(
                level: "L0",
                score10: 7,
                strengths: ["Good engagement with the concept", "Clear personal connection"],
                improvements: ["Could explore practical applications more", "Consider deeper analysis"]
            ),
            userResponse: "This is my response about Norman Doors...",
            level: 0,
            openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
        )
    }
} 