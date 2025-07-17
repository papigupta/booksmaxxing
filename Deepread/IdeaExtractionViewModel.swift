import Foundation
import SwiftUI

@MainActor
class IdeaExtractionViewModel: ObservableObject {
    @Published var extractedIdeas: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let openAIService: OpenAIService
    
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }
    
    func extractIdeas(from title: String) {
        print("DEBUG: extractIdeas called with title: \(title)")
        guard !title.isEmpty else {
            print("DEBUG: Received empty title — skipping")
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Book title is empty"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        
        print("DEBUG: Normalized title: '\(normalizedTitle)'")
        
        Task {
            do {
                print("DEBUG: Calling OpenAI with title: \(normalizedTitle)")
                let ideas = try await openAIService.extractIdeas(from: normalizedTitle)
                print("DEBUG: Raw response content: \(ideas)")
                self.extractedIdeas = ideas
                self.isLoading = false
            } catch {
                print("DEBUG: Error occurred: \(error)")
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
} 