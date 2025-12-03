//
//  BooksmaxxingApp.swift
//  Booksmaxxing
//
//  Created by Prakhar Gupta on 17/07/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseCrashlytics

@main
    
struct BooksmaxxingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @Environment(\.scenePhase) private var scenePhase
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
    // Theme state
    @StateObject private var themeManager = ThemeManager()
    
    // Track active persistence containers
    @State private var cloudModelContainer = BooksmaxxingApp.makeCloudModelContainer()
    @State private var guestModelContainer = BooksmaxxingApp.makeGuestModelContainer()
    // Theme preset for global visual filter
    @State private var themePreset: ThemePreset = .system // treat as System Light by default

    private func setupCloudKitIfNeeded() {}
    
    private func setupPersistentStorage() {}
    
    private var activeModelContainer: ModelContainer {
        if authManager.isSignedIn && !authManager.isGuestSession {
            return cloudModelContainer
        } else {
            return guestModelContainer
        }
    }
    
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
                            .environmentObject(themeManager)
                            .transition(.opacity)
                    } else {
                        AuthView(authManager: authManager)
                            .transition(.opacity)
                    }
                }
            }
            // Apply experimental theme globally
            .applyTheme(themePreset)
            .preferredColorScheme(themePreset.preferredColorScheme)
            .animation(.easeInOut(duration: 0.5), value: isShowingSplash)
            .onAppear {
                // Hide splash screen after a delay to allow everything to load
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isShowingSplash = false
                    }
                }
                // Storage already initialized via the active model container
            }
            // Removed global Experiments FAB overlay; access Experiments from kebab menu in BookOverviewView.
        }
        .modelContainer(activeModelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                streakManager.refreshNotificationSchedule()
            }
        }
        .onChange(of: authManager.isSignedIn) { _, signedIn in
            if !signedIn && !authManager.isGuestSession {
                guestModelContainer = BooksmaxxingApp.makeGuestModelContainer()
            }
        }
        .onChange(of: authManager.isGuestSession) { _, isGuest in
            if isGuest {
                guestModelContainer = BooksmaxxingApp.makeGuestModelContainer()
            }
        }
    }
}

private extension BooksmaxxingApp {
    static func makeCloudModelContainer() -> ModelContainer {
        do {
            let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)
            let container = try makeModelContainer(configuration: cloudConfig)
            print("✅ Created CloudKit-backed ModelContainer")
            return container
        } catch {
            print("❌ CloudKit container failed: \(error)")
            return makeGuestModelContainer()
        }
    }

    static func makeGuestModelContainer() -> ModelContainer {
        do {
            let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try makeModelContainer(configuration: inMemory)
            print("✅ Created in-memory ModelContainer")
            return container
        } catch {
            print("❌ Failed to create in-memory container: \(error)")
            fatalError("Cannot create guest ModelContainer")
        }
    }

    static func makeModelContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Book.self,
                 Idea.self,
                 Progress.self,
                 Primer.self,
                 Question.self,
                 Test.self,
                 TestAttempt.self,
                 QuestionResponse.self,
                 TestProgress.self,
                 DailyCognitiveStats.self,
                 PracticeSession.self,
                 ReviewQueueItem.self,
                 IdeaCoverage.self,
                 MissedQuestionRecord.self,
                 StoredLesson.self,
                 PrimerLinkItem.self,
                 StreakState.self,
                 UserProfile.self,
                 BookTheme.self,
            configurations: configuration
        )
    }
}
