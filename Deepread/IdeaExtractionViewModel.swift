import Foundation
import SwiftUI

@MainActor
class IdeaExtractionViewModel: ObservableObject {
    @Published var extractedIdeas: [Idea] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let openAIService: OpenAIService
    private let bookService: BookService
    private var currentTask: Task<Void, Never>?
    private var currentBookTitle: String = ""
    
    init(openAIService: OpenAIService, bookService: BookService) {
        self.openAIService = openAIService
        self.bookService = bookService
    }
    
    deinit {
        currentTask?.cancel()
    }
    
    func loadOrExtractIdeas(from title: String) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Book title is empty"
            return
        }
        
        currentBookTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First, try to load existing ideas
        do {
            if let existingBook = try bookService.getBook(withTitle: currentBookTitle) {
                print("DEBUG: Found existing book with \(existingBook.ideas.count) ideas")
                // CRITICAL: Sort ideas by ID to maintain consistent order
                self.extractedIdeas = existingBook.ideas.sorted { idea1, idea2 in
                    idea1.id < idea2.id
                }
                print("DEBUG: Ideas loaded in order: \(self.extractedIdeas.map { $0.id })")
                self.isLoading = false
                self.errorMessage = nil
                return
            }
        } catch {
            print("DEBUG: Error loading existing book: \(error)")
        }
        
        // If no existing ideas found, extract them
        await extractIdeas(from: title)
    }
    
    private func extractIdeas(from title: String) async {
        // Cancel any existing task
        currentTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        
        currentTask = Task {
            do {
                print("DEBUG: Starting idea extraction for: \(normalizedTitle)")
                let ideas = try await openAIService.extractIdeas(from: normalizedTitle)
                
                // Check if task was cancelled
                try Task.checkCancellation()
                
                let parsedIdeas = ideas.compactMap { line -> Idea? in
                    let parts = line.split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count >= 2 else { return nil }

                    let id = parts[0]
                    let fullTitleWithExplanation = parts[1]
                    let depthTarget = parts.count > 2 ? Int(parts[2]) ?? 1 : 1
                    
                    let titleDescriptionParts = fullTitleWithExplanation.split(separator: "—", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    let ideaTitle = titleDescriptionParts[0]
                    let description = titleDescriptionParts.count > 1 ? titleDescriptionParts[1] : ""

                    return Idea(id: id, title: ideaTitle, description: description, bookTitle: currentBookTitle, depthTarget: depthTarget, masteryLevel: 0, lastPracticed: nil)
                }
                
                print("DEBUG: Parsed \(parsedIdeas.count) ideas")
                
                // Save to database
                do {
                    let book = try bookService.findOrCreateBook(title: currentBookTitle)
                    try bookService.saveIdeas(parsedIdeas, for: book)
                    self.extractedIdeas = parsedIdeas
                    print("DEBUG: Successfully saved ideas to database")
                } catch {
                    print("DEBUG: Error saving ideas: \(error)")
                    // Even if saving fails, show the ideas to the user
                    self.extractedIdeas = parsedIdeas
                }
                
                self.isLoading = false
                self.errorMessage = nil
            } catch is CancellationError {
                print("DEBUG: Idea extraction was cancelled")
                // Don't update UI state if cancelled
            } catch {
                print("DEBUG: Idea extraction failed with error: \(error)")
                self.errorMessage = "Failed to extract ideas. Please check your internet connection and try again."
                self.isLoading = false
                
                // Try to load existing ideas as fallback
                do {
                    if let existingBook = try bookService.getBook(withTitle: currentBookTitle) {
                        print("DEBUG: Loading existing ideas as fallback")
                        self.extractedIdeas = existingBook.ideas
                        self.errorMessage = nil
                    }
                } catch {
                    print("DEBUG: Failed to load existing ideas as fallback: \(error)")
                }
            }
        }
    }
    
    func cancelExtraction() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
    
    // Method to refresh ideas from the database
    func refreshIdeas() async {
        guard !currentBookTitle.isEmpty else { return }
        
        do {
            if let existingBook = try bookService.getBook(withTitle: currentBookTitle) {
                print("DEBUG: Refreshing ideas from database")
                // CRITICAL: Sort ideas by ID to maintain consistent order
                self.extractedIdeas = existingBook.ideas.sorted { idea1, idea2 in
                    idea1.id < idea2.id
                }
                print("DEBUG: Ideas refreshed in order: \(self.extractedIdeas.map { $0.id })")
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch {
            print("DEBUG: Error refreshing ideas: \(error)")
        }
    }
}
