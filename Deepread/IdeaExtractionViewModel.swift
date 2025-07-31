import Foundation
import SwiftUI

@MainActor
class IdeaExtractionViewModel: ObservableObject {
    @Published var extractedIdeas: [Idea] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var bookInfo: BookInfo?
    
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
    
    func loadOrExtractIdeas(from input: String) async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Book input is empty"
            return
        }
        
        // Cancel any existing task
        currentTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        currentTask = Task {
            do {
                // Step 1: Extract book info (title and author)
                print("DEBUG: Extracting book info from: '\(input)'")
                let extractedBookInfo = try await openAIService.extractBookInfo(from: input)
                
                // Check if task was cancelled
                try Task.checkCancellation()
                
                await MainActor.run {
                    self.bookInfo = extractedBookInfo
                    self.currentBookTitle = extractedBookInfo.title
                }
                
                print("DEBUG: Extracted book info - Title: '\(extractedBookInfo.title)', Author: \(extractedBookInfo.author ?? "nil")")
                print("DEBUG: Original input: '\(input)' → Corrected title: '\(extractedBookInfo.title)'")
                
                // Step 2: Try to load existing ideas first
                do {
                    if let existingBook = try bookService.getBook(withTitle: extractedBookInfo.title) {
                        print("DEBUG: Found existing book with \(existingBook.ideas.count) ideas")
                        await MainActor.run {
                            self.extractedIdeas = existingBook.ideas.sorted { idea1, idea2 in
                                idea1.id < idea2.id
                            }
                            self.isLoading = false
                            self.errorMessage = nil
                        }
                        return
                    }
                } catch {
                    print("DEBUG: Error loading existing book: \(error)")
                }
                
                // Step 3: Extract ideas if no existing book found
                await extractIdeas(from: extractedBookInfo.title)
                
                // Step 4: If no author was found but ideas were extracted, try to get author from the ideas context
                if extractedBookInfo.author == nil && !self.extractedIdeas.isEmpty {
                    print("DEBUG: No author found initially, but ideas were extracted. Trying to identify author from context...")
                    await tryExtractAuthorFromContext(bookTitle: extractedBookInfo.title)
                }
                
            } catch is CancellationError {
                print("DEBUG: Book info extraction was cancelled")
                // Don't update UI state if cancelled
            } catch {
                print("DEBUG: Book info extraction failed with error: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to extract book information. Please check your internet connection and try again."
                    self.isLoading = false
                }
            }
        }
    }
    
    private func extractIdeas(from title: String) async {
        do {
            print("DEBUG: Starting idea extraction for: '\(title)'")
            let ideas = try await openAIService.extractIdeas(from: title, author: bookInfo?.author)
            
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

                // Use the corrected book title from BookInfo instead of user input
                let correctedBookTitle = bookInfo?.title ?? currentBookTitle
                return Idea(id: id, title: ideaTitle, description: description, bookTitle: correctedBookTitle, depthTarget: depthTarget, masteryLevel: 0, lastPracticed: nil, currentLevel: nil)
            }
            
            print("DEBUG: Parsed \(parsedIdeas.count) ideas")
            
            // Save to database with author information
            do {
                let book = try bookService.findOrCreateBook(title: currentBookTitle, author: bookInfo?.author)
                try bookService.saveIdeas(parsedIdeas, for: book)
                await MainActor.run {
                    self.extractedIdeas = parsedIdeas
                }
                print("DEBUG: Successfully saved ideas to database")
            } catch {
                print("DEBUG: Error saving ideas: \(error)")
                // Even if saving fails, show the ideas to the user
                await MainActor.run {
                    self.extractedIdeas = parsedIdeas
                }
            }
            
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = nil
            }
            
        } catch is CancellationError {
            print("DEBUG: Idea extraction was cancelled")
            // Don't update UI state if cancelled
        } catch {
            print("DEBUG: Idea extraction failed with error: \(error)")
            await MainActor.run {
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
    
    // Method to try to extract author from context when initial extraction fails
    private func tryExtractAuthorFromContext(bookTitle: String) async {
        do {
            let systemPrompt = """
            You are an expert at identifying book authors from context.
            
            TASK:
            Based on the book title and the ideas extracted from it, identify the most likely author of the book.
            
            BOOK TITLE: "\(bookTitle)"
            
            EXTRACTED IDEAS:
            \(self.extractedIdeas.prefix(5).map { "- \($0.title): \($0.ideaDescription)" }.joined(separator: "\n"))
            
            INSTRUCTIONS:
            1. Analyze the ideas and book title to identify the most likely author
            2. Consider the themes, concepts, and writing style suggested by the ideas
            3. If you can confidently identify the author, return their name
            4. If you're uncertain, return null
            
            Return ONLY the author name or null, nothing else.
            """
            
            let requestBody = ChatRequest(
                model: "gpt-3.5-turbo",
                messages: [
                    Message(role: "system", content: systemPrompt),
                    Message(role: "user", content: "Who is the most likely author of this book based on the ideas?")
                ],
                max_tokens: 100,
                temperature: 0.1
            )
            
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(Secrets.openAIAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            
            let chatResponse: ChatResponse
            do {
                chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            } catch {
                return
            }
            
            guard let content = chatResponse.choices.first?.message.content else {
                return
            }
            
            let authorName = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !authorName.isEmpty && authorName.lowercased() != "null" && authorName.lowercased() != "unknown" {
                print("DEBUG: Successfully identified author from context: \(authorName)")
                
                // Update the book info with the found author
                await MainActor.run {
                    self.bookInfo = BookInfo(title: bookTitle, author: authorName)
                }
                
                // Update the database with the author information
                do {
                    try bookService.updateBookAuthor(title: bookTitle, author: authorName)
                } catch {
                    print("DEBUG: Failed to update book with author information: \(error)")
                }
            } else {
                print("DEBUG: Could not identify author from context")
            }
            
        } catch {
            print("DEBUG: Error trying to extract author from context: \(error)")
        }
    }
}
