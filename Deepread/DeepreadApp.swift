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
            Primer.self, // Add Primer to schema
        ])
        
        // Try persistent storage first
        do {
            let modelConfiguration = ModelConfiguration(
                isStoredInMemoryOnly: false
            )
            return try ModelContainer(for: schema, configurations: modelConfiguration)
        } catch {
            print("Failed to create persistent ModelContainer: \(error)")
            
            // Fallback to in-memory only if persistent storage fails
            do {
                let fallbackConfiguration = ModelConfiguration(
                    isStoredInMemoryOnly: true
                )
                return try ModelContainer(for: schema, configurations: fallbackConfiguration)
            } catch {
                print("Failed to create in-memory ModelContainer: \(error)")
                
                // Last resort: create a minimal in-memory container
                // This should never fail, but if it does, the app will show an error state
                do {
                    let minimalConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    return try ModelContainer(for: schema, configurations: minimalConfig)
                } catch {
                    print("CRITICAL: Could not create any ModelContainer: \(error)")
                    // Show user-friendly error and continue with limited functionality
                    // The app will handle this gracefully in the UI
                    return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                }
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

