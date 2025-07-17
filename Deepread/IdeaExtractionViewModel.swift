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
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Book title is empty"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        
        #if DEBUG
        print("DEBUG: Normalized title: '\(normalizedTitle)'")
        #endif
        
        Task {
            do {
                #if DEBUG
                print("DEBUG: Calling OpenAI with title: \(normalizedTitle)")
                #endif
                let ideas = try await openAIService.extractIdeas(from: normalizedTitle)
                self.extractedIdeas = ideas
                self.isLoading = false
            } catch {
                #if DEBUG
                print("DEBUG: Error occurred: \(error)")
                #endif
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
