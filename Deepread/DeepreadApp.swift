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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            Idea.self,
            UserResponse.self,
            Progress.self,
        ])
        let modelConfiguration = ModelConfiguration(
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: modelConfiguration)
        } catch {
            print("Failed to create ModelContainer: \(error)")
            // Fallback to in-memory only if persistent storage fails
            let fallbackConfiguration = ModelConfiguration(
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: schema, configurations: fallbackConfiguration)
            } catch {
                fatalError("Could not create ModelContainer even with fallback: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            OnboardingView(openAIService: openAIService)
        }
        .modelContainer(sharedModelContainer)
    }
}
