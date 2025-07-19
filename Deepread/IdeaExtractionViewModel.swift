import Foundation
import SwiftUI

@MainActor
class IdeaExtractionViewModel: ObservableObject {
    @Published var extractedIdeas: [Idea] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let openAIService: OpenAIService
    private var currentTask: Task<Void, Never>?
    private var currentBookTitle: String = ""
    
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
        
        // Store the original book title for use in Idea creation
        currentBookTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
                
                let parsedIdeas = ideas.compactMap { line -> Idea? in
                    // Format: "i7 | Anchoring effect — Explanation"
                    let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2 else { return nil }

                    let id = parts[0]                          // "i7"
                    let fullTitleWithExplanation = parts[1]    // "Anchoring effect — Explanation"
                    
                    // Split title and description by "—"
                    let titleDescriptionParts = fullTitleWithExplanation.split(separator: "—", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    let title = titleDescriptionParts[0]
                    let description = titleDescriptionParts.count > 1 ? titleDescriptionParts[1] : ""

                    return Idea(id: id, title: title, description: description, bookTitle: currentBookTitle)
                }
                
                self.extractedIdeas = parsedIdeas
                
                print("🧠 Parsed ideas:")
                for idea in self.extractedIdeas {
                    print("ID: \(idea.id), Title: \(idea.title)")
                }
                
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
