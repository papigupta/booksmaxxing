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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            Idea.self,
            UserResponse.self,
            Progress.self,
            Primer.self
        ])
        
        do {
            // Try to create persistent container with default configuration
            let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: modelConfiguration)
            print("✅ Successfully created persistent ModelContainer")
            return container
        } catch {
            print("⚠️  Failed to create persistent ModelContainer: \(error)")
            
            // For migration issues, try to reset the data store
            if error.localizedDescription.contains("migration") || error.localizedDescription.contains("schema") || error.localizedDescription.contains("model") {
                print("🔄 Detected schema migration issue - attempting to reset data store")
                
                // Try to get the default store location and delete it
                let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                if let storeDirectory = appSupportURL?.appendingPathComponent("default.store") {
                    try? FileManager.default.removeItem(at: storeDirectory)
                    print("🗑️  Attempted to delete existing data store")
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
                    print("✅ Successfully created fresh ModelContainer after reset")
                    return freshContainer
                } catch {
                    print("❌ Failed to create container even after reset: \(error)")
                }
            }
            
            // Final fallback to in-memory storage
            print("⚠️  Falling back to in-memory storage - data will not persist between app launches")
            do {
                let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                let inMemoryContainer = try ModelContainer(for: schema, configurations: inMemoryConfig)
                print("ℹ️  Successfully created in-memory ModelContainer")
                return inMemoryContainer
            } catch {
                fatalError("CRITICAL: Cannot create even in-memory ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashScreenView()
                        .transition(.opacity)
                } else {
                    OnboardingView(openAIService: openAIService)
                        .onAppear {
                            // Run migration for existing data
                            Task {
                                do {
                                    let bookService = BookService(modelContext: sharedModelContainer.mainContext)
                                    try await bookService.migrateExistingDataToBookSpecificIds()
                                } catch {
                                    print("DEBUG: Migration failed: \(error)")
                                }
                            }
                        }
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

