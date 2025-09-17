//
//  DeepreadApp.swift
//  Deepread
//
//  Created by Prakhar Gupta on 17/07/25.
//

import SwiftUI
import SwiftData

@main
struct DeepreadApp: App {
    // Shared OpenAIService instance
    private let openAIService = OpenAIService(apiKey: Secrets.openAIAPIKey)
    
    // State to control splash screen visibility
    @State private var isShowingSplash = true
    
    // Navigation state
    @StateObject private var navigationState = NavigationState()
    // Streak state
    @StateObject private var streakManager = StreakManager()
    // Auth state
    @StateObject private var authManager = AuthManager()
    
    // Track if we should try CloudKit sync
    @State private var shouldEnableCloudKit = false
    @State private var cloudKitContainer: ModelContainer?
    @State private var persistentContainer: ModelContainer?
    
    var sharedModelContainer: ModelContainer = {
        do {
            let cloudConfig = ModelConfiguration(
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(
                for: Book.self,
                     Idea.self,
                     Progress.self,
                     Primer.self,
                     Question.self,
                     Test.self,
                     TestAttempt.self,
                     QuestionResponse.self,
                     TestProgress.self,
                     PracticeSession.self,
                     ReviewQueueItem.self,
                     IdeaCoverage.self,
                     MissedQuestionRecord.self,
                     StoredLesson.self,
                     PrimerLinkItem.self,
                     StreakState.self,
                     UserProfile.self,
                configurations: cloudConfig
            )
            print("✅ Created CloudKit-backed ModelContainer")
            return container
        } catch {
            print("❌ CloudKit container failed: \(error)")
            // Fallback to in-memory only
            do {
                let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: Book.self,
                         Idea.self,
                         Progress.self,
                         Primer.self,
                         Question.self,
                         Test.self,
                         TestAttempt.self,
                         QuestionResponse.self,
                         TestProgress.self,
                         PracticeSession.self,
                         ReviewQueueItem.self,
                         IdeaCoverage.self,
                         MissedQuestionRecord.self,
                         StoredLesson.self,
                         PrimerLinkItem.self,
                         StreakState.self,
                         UserProfile.self,
                    configurations: inMemory
                )
                print("✅ Created in-memory ModelContainer")
                return container
            } catch {
                print("❌ In-memory container failed: \(error)")
                fatalError("Cannot create any ModelContainer at all")
            }
        }
    }()

    private func setupCloudKitIfNeeded() {}
    
    private func setupPersistentStorage() {}
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashScreenView()
                        .transition(.opacity)
                } else {
                    if authManager.isSignedIn {
                        MainView(openAIService: openAIService)
                            .environmentObject(navigationState)
                            .environmentObject(streakManager)
                            .environmentObject(authManager)
                            .transition(.opacity)
                    } else {
                        AuthView(authManager: authManager)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isShowingSplash)
            .onAppear {
                // Hide splash screen after a delay to allow everything to load
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isShowingSplash = false
                    }
                }
                // Storage already initialized via sharedModelContainer
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
