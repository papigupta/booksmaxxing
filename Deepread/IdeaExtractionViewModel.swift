import Foundation
import SwiftUI

@MainActor
class IdeaExtractionViewModel: ObservableObject {
    @Published var extractedIdeas: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let openAIService: OpenAIService
    private var currentTask: Task<Void, Never>?
    
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }
    
    deinit {
        currentTask?.cancel()
    }
    
    func extractIdeas(from title: String) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Book title is empty"
            return
        }
        
        // Cancel any existing task
        currentTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        
        #if DEBUG
        print("DEBUG: Normalized title: '\(normalizedTitle)'")
        #endif
        
        currentTask = Task {
            do {
                #if DEBUG
                print("DEBUG: Calling OpenAI with title: \(normalizedTitle)")
                #endif
                let ideas = try await openAIService.extractIdeas(from: normalizedTitle)
                
                // Check if task was cancelled
                try Task.checkCancellation()
                
                self.extractedIdeas = ideas
                self.isLoading = false
            } catch is CancellationError {
                #if DEBUG
                print("DEBUG: Task was cancelled")
                #endif
                // Don't update UI state if cancelled
            } catch {
                #if DEBUG
                print("DEBUG: Error occurred: \(error)")
                #endif
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func cancelExtraction() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
}
