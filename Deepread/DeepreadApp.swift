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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            Idea.self,
            Progress.self,
            Primer.self,
            // Test system models
            Question.self,
            Test.self,
            TestAttempt.self,
            QuestionResponse.self,
            TestProgress.self,
            PracticeSession.self,
            // Review queue models
            ReviewQueueItem.self,
            // Coverage tracking models
            IdeaCoverage.self,
            MissedQuestionRecord.self,
            // Legacy model for migration
            IdeaMastery.self
        ])
        
        do {
            // Try to create persistent container with default configuration
            let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: modelConfiguration)
            print("✅ Successfully created persistent ModelContainer")
            
            // One-time migration from old mastery to new coverage system
            let migrationKey = "coverageMigrationV1Done"
            let alreadyMigrated = UserDefaults.standard.bool(forKey: migrationKey)
            if !alreadyMigrated {
                let migrationService = CoverageMigrationService(modelContext: container.mainContext)
                migrationService.migrateOldMasteryToCoverage()
                UserDefaults.standard.set(true, forKey: migrationKey)
            }

            // Backfill bookId for any legacy ReviewQueueItems missing it
            do {
                let ctx = container.mainContext
                let descriptor = FetchDescriptor<ReviewQueueItem>(
                    predicate: #Predicate<ReviewQueueItem> { item in item.bookId == nil }
                )
                let legacyItems = try ctx.fetch(descriptor)
                if !legacyItems.isEmpty {
                    let bookService = BookService(modelContext: ctx)
                    for item in legacyItems {
                        if let book = try? bookService.getBook(withTitle: item.bookTitle) {
                            item.bookId = book.id.uuidString
                        }
                    }
                    try? ctx.save()
                    print("✅ Backfilled bookId for \(legacyItems.count) ReviewQueueItems")
                }
            } catch {
                print("⚠️  Backfill for ReviewQueueItem.bookId failed: \(error)")
            }
            
            return container
        } catch {
            print("⚠️  Failed to create persistent ModelContainer: \(error)")
            
            // Only reset for actual incompatible schema changes, not for generic errors
            // Check for specific CoreData/SwiftData migration errors
            let errorString = String(describing: error)
            if errorString.contains("The model used to open the store is incompatible") ||
               errorString.contains("Failed to find a unique match for an NSEntityDescription") ||
               errorString.contains("Cannot migrate store in-place") ||
               errorString.contains("loadIssueModelContainer") {
                print("🔄 Detected incompatible schema change - attempting controlled migration")
                
                // Try to get the default store location and delete it
                let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                if let storeDirectory = appSupportURL?.appendingPathComponent("default.store") {
                    try? FileManager.default.removeItem(at: storeDirectory)
                    print("🗑️  Deleted existing incompatible data store")
                }
                
                // Also try deleting common SwiftData store locations
                if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let swiftDataStore = documentsURL.appendingPathComponent("default.store")
                    try? FileManager.default.removeItem(at: swiftDataStore)
                }
                
                // Try creating container again with fresh store
                do {
                    let freshConfig = ModelConfiguration(isStoredInMemoryOnly: false)
                    let freshContainer = try ModelContainer(for: schema, configurations: freshConfig)
                    print("✅ Successfully created fresh persistent ModelContainer after migration")
                    return freshContainer
                } catch {
                    print("❌ Failed to create container even after migration: \(error)")
                    // Fall through to fatal error - don't use in-memory as fallback
                    fatalError("CRITICAL: Cannot create ModelContainer after migration: \(error)")
                }
            }
            
            // For other errors, don't fall back to in-memory - fail fast
            // This ensures we catch persistence issues during development
            fatalError("CRITICAL: Cannot create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashScreenView()
                        .transition(.opacity)
                } else {
                    MainView(openAIService: openAIService)
                        .environmentObject(navigationState)
                        .transition(.opacity)
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
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
