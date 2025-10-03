import Foundation
import SwiftUI
import OSLog

@MainActor
class IdeaExtractionViewModel: ObservableObject {
    @Published var extractedIdeas: [Idea] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var bookInfo: BookInfo?
    @Published var currentBook: Book?
    
    private let openAIService: OpenAIService
    private let bookService: BookService
    private var currentTask: Task<Void, Never>?
    private var currentBookTitle: String = ""
    private var metadata: BookMetadata?
    private let logger = Logger(subsystem: "com.booksmaxxing.app", category: "IdeaExtraction")
    
    init(openAIService: OpenAIService, bookService: BookService) {
        self.openAIService = openAIService
        self.bookService = bookService
    }
    
    deinit {
        currentTask?.cancel()
    }
    
    // MARK: - Helper Functions
    
    /// Ensures consistent ordering of ideas by numeric ID (i1, i2, i3, i10, i11, etc.)
    private func sortedIdeas(_ ideas: [Idea]) -> [Idea] {
        return ideas.sortedByNumericId()
    }
    
    /// Updates extractedIdeas with proper sorting and logging
    private func updateExtractedIdeas(_ ideas: [Idea], source: String) {
        let sortedIdeas = sortedIdeas(ideas)
        self.extractedIdeas = sortedIdeas
        print("DEBUG: Updated extractedIdeas from \(source) with \(sortedIdeas.count) ideas in order: \(sortedIdeas.map { $0.id })")
    }
    
    func loadOrExtractIdeas(from input: String, metadata incomingMetadata: BookMetadata? = nil) async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Book input is empty"
            return
        }
        
        // Cancel any existing task
        currentTask?.cancel()

        isLoading = true
        errorMessage = nil
        if let incomingMetadata {
            metadata = incomingMetadata
        }

        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // OPTIMIZATION: First try exact match with input to avoid LLM call for existing books
                print("DEBUG: Checking for exact match with input: '\(input)'")
                do {
                    if let existingBook = try self.bookService.getBook(withTitle: input) {
                        print("DEBUG: Found exact match! Loading existing book with \(((existingBook.ideas ?? []).count)) ideas")
                        
                        // If book exists but has no ideas, continue with idea extraction
                        if (existingBook.ideas ?? []).isEmpty {
                            print("DEBUG: Book exists but has no ideas, continuing with extraction")
                            let localMetadata = incomingMetadata ?? self.metadata ?? self.metadata(from: existingBook)
                            await MainActor.run {
                                self.currentBookTitle = existingBook.title
                                self.bookInfo = BookInfo(title: existingBook.title, author: existingBook.author)
                                self.currentBook = existingBook
                                if let localMetadata { self.metadata = localMetadata }
                            }

                            if let metadataToUse = localMetadata {
                                print("DEBUG: Using provided metadata for extraction (Google ID: \(metadataToUse.googleBooksId))")
                                await self.extractIdeas(
                                    from: metadataToUse.title,
                                    originalInput: input,
                                    metadata: metadataToUse
                                )
                                return
                            }
                            // Continue to idea extraction below without metadata
                        } else {
                            // Sort the book's ideas to ensure consistency
                            existingBook.ideas = (existingBook.ideas ?? []).sortedByNumericId()
                            
                            await MainActor.run {
                                self.updateExtractedIdeas((existingBook.ideas ?? []), source: "exact match")
                                self.isLoading = false
                                self.errorMessage = nil
                                self.currentBookTitle = existingBook.title
                                // Set book info from existing book
                                self.bookInfo = BookInfo(title: existingBook.title, author: existingBook.author)
                                self.currentBook = existingBook
                            }
                            // Prefetch Lesson 1 for existing book path (no save happening)
                            let prefetcher = PracticePrefetcher(modelContext: self.bookService.modelContextRef, openAIService: self.openAIService)
                            prefetcher.prefetchLesson(book: existingBook, lessonNumber: 1)
                            return
                        }
                    }
                } catch {
                    print("DEBUG: Error checking for exact match: \(error)")
                }
                
                // Step 1: Extract book info (title and author) - only if no exact match found
                print("DEBUG: No exact match found. Extracting book info from: '\(input)'")
                let extractedBookInfo = try await self.openAIService.extractBookInfo(from: input)
                
                // Check if task was cancelled
                try Task.checkCancellation()
                
                await MainActor.run {
                    self.bookInfo = extractedBookInfo
                    self.currentBookTitle = extractedBookInfo.title
                }
                
                print("DEBUG: Extracted book info - Title: '\(extractedBookInfo.title)', Author: \(extractedBookInfo.author ?? "nil")")
                print("DEBUG: Original input: '\(input)' → Corrected title: '\(extractedBookInfo.title)'")
                
                // Step 2: Try to load existing ideas with corrected title
                do {
                    if let existingBook = try self.bookService.getBook(withTitle: extractedBookInfo.title) {
                        print("DEBUG: Found existing book with corrected title with \(((existingBook.ideas ?? []).count)) ideas")
                        
                        // If book exists but has no ideas, continue with idea extraction
                        if (existingBook.ideas ?? []).isEmpty {
                            print("DEBUG: Book with corrected title exists but has no ideas, continuing with extraction")
                            let localMetadata = incomingMetadata ?? self.metadata ?? self.metadata(from: existingBook)
                            await MainActor.run {
                                self.currentBook = existingBook
                                if let localMetadata { self.metadata = localMetadata }
                            }
                            if let metadataToUse = localMetadata {
                                await self.extractIdeas(
                                    from: metadataToUse.title,
                                    originalInput: input,
                                    metadata: metadataToUse
                                )
                                return
                            }
                            // Continue to idea extraction below without metadata
                        } else {
                            // Sort the book's ideas to ensure consistency
                            existingBook.ideas = (existingBook.ideas ?? []).sortedByNumericId()
                            
                            await MainActor.run {
                                self.updateExtractedIdeas((existingBook.ideas ?? []), source: "corrected title match")
                                self.isLoading = false
                                self.errorMessage = nil
                                self.currentBook = existingBook
                            }
                            // Prefetch Lesson 1 for corrected-title existing book path
                            let prefetcher = PracticePrefetcher(modelContext: self.bookService.modelContextRef, openAIService: self.openAIService)
                            prefetcher.prefetchLesson(book: existingBook, lessonNumber: 1)
                            return
                        }
                    }
                } catch {
                    print("DEBUG: Error loading existing book with corrected title: \(error)")
                }
                
                // Step 3: Extract ideas if no existing book found
                // Pass the original input as well so we can update the correct book
                await self.extractIdeas(from: extractedBookInfo.title, originalInput: input, metadata: self.metadata)
                
                // Step 4: If no author was found but ideas were extracted, try to get author from the ideas context
                if extractedBookInfo.author == nil && !self.extractedIdeas.isEmpty {
                    print("DEBUG: No author found initially, but ideas were extracted. Trying to identify author from context...")
                    await self.tryExtractAuthorFromContext(bookTitle: extractedBookInfo.title)
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
        currentTask = task
        await task.value
    }
    
    private func extractIdeas(from title: String, originalInput: String? = nil, metadata: BookMetadata? = nil) async {
        do {
            print("DEBUG: Starting idea extraction for: '\(title)'")
            let ideas = try await openAIService.extractIdeas(from: title, author: bookInfo?.author, metadata: metadata)
            
            // Check if task was cancelled
            try Task.checkCancellation()
            
            let parsedIdeas = ideas.compactMap { line -> Idea? in
                let parts = line.split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2 else { return nil }

                let id = parts[0]
                let fullTitleWithExplanation = parts[1]
                let importanceString = parts.count >= 3 ? parts[2] : "Building Block"
                let depthTarget = 1 // Default value since we removed this from AI output
                
                let titleDescriptionParts = fullTitleWithExplanation.split(separator: "—", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let ideaTitle = titleDescriptionParts[0]
                let description = titleDescriptionParts.count > 1 ? titleDescriptionParts[1] : ""

                // Parse importance level
                let importance: ImportanceLevel = {
                    switch importanceString.lowercased() {
                    case "foundation": return .foundation
                    case "enhancement": return .enhancement
                    default: return .buildingBlock
                    }
                }()

                // Use the corrected book title from BookInfo instead of user input
                let correctedBookTitle = bookInfo?.title ?? currentBookTitle
                return Idea(id: id, title: ideaTitle, description: description, bookTitle: correctedBookTitle, depthTarget: depthTarget, masteryLevel: 0, lastPracticed: nil, currentLevel: nil, importance: importance)
            }
            
            print("DEBUG: Parsed \(parsedIdeas.count) ideas")
            
            // Save to database with author information
            do {
                // Use the original input title to find the initial book and update it
                let book = try bookService.updateBookDetails(
                    oldTitle: originalInput ?? title,  // Use the original input title if available
                    newTitle: currentBookTitle,  // Update to the corrected title
                    author: bookInfo?.author
                )
                if let metadata = metadata ?? self.metadata {
                    self.bookService.applyMetadata(metadata, to: book)
                }
                try bookService.saveIdeas(parsedIdeas, for: book)
                // Ensure book.ideas is sorted after saving
                book.ideas = (book.ideas ?? []).sortedByNumericId()
                await MainActor.run {
                    self.updateExtractedIdeas(parsedIdeas, source: "fresh extraction")
                    self.currentBook = book
                }
                print("DEBUG: Successfully saved ideas to database")
                // Backend trigger: prefetch Lesson 1 immediately after ideas are saved
                let prefetcher = PracticePrefetcher(modelContext: self.bookService.modelContextRef, openAIService: self.openAIService)
                prefetcher.prefetchLesson(book: book, lessonNumber: 1)
                print("DEBUG: Prefetch for Lesson 1 triggered from IdeaExtractionViewModel after save")
                // After updating title/author, force-refresh Google Books metadata to improve cover accuracy
                if book.googleBooksId == nil {
                    Task { await self.bookService.fetchAndUpdateBookMetadata(for: book, force: true) }
                }
            } catch {
                print("DEBUG: Error saving ideas: \(error)")
                // Even if saving fails, show the ideas to the user
                await MainActor.run {
                    self.updateExtractedIdeas(parsedIdeas, source: "fresh extraction (save failed)")
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
                
                // Try to load existing ideas as fallback - FIXED: Now includes sorting
                do {
                    if let existingBook = try self.bookService.getBook(withTitle: self.currentBookTitle) {
                        print("DEBUG: Loading existing ideas as fallback")
                        self.updateExtractedIdeas((existingBook.ideas ?? []), source: "error fallback")
                        self.errorMessage = nil
                    }
                } catch {
                    print("DEBUG: Failed to load existing ideas as fallback: \(error)")
                }
            }
        }
    }

    private func metadata(from book: Book) -> BookMetadata? {
        guard let googleId = book.googleBooksId else { return nil }
        let authors = book.author.map { [$0] } ?? []
        let categories = book.categories?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return BookMetadata(
            googleBooksId: googleId,
            title: book.title,
            subtitle: book.subtitle,
            description: book.bookDescription,
            authors: authors,
            publisher: book.publisher,
            language: book.language,
            categories: categories,
            publishedDate: book.publishedDate,
            thumbnailUrl: book.thumbnailUrl,
            coverImageUrl: book.coverImageUrl,
            averageRating: book.averageRating,
            ratingsCount: book.ratingsCount,
            previewLink: book.previewLink,
            infoLink: book.infoLink
        )
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
                self.updateExtractedIdeas((existingBook.ideas ?? []), source: "refresh")
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch {
            print("DEBUG: Error refreshing ideas: \(error)")
        }
    }
    
    // Method to refresh ideas only if user has been practicing (to update mastery levels)
    func refreshIdeasIfNeeded() async {
        guard !currentBookTitle.isEmpty else { return }
        
        do {
            if let existingBook = try bookService.getBook(withTitle: currentBookTitle) {
                // Only refresh if any idea has different mastery level or last practiced date
                let currentIdeaMap = Dictionary(uniqueKeysWithValues: extractedIdeas.map { ($0.id, ($0.masteryLevel, $0.lastPracticed)) })
                let needsRefresh = (existingBook.ideas ?? []).contains { idea in
                    guard let current = currentIdeaMap[idea.id] else { return true }
                    return current.0 != idea.masteryLevel || current.1 != idea.lastPracticed
                }
                
                if needsRefresh {
                    print("DEBUG: Ideas have changed, refreshing from database")
                    self.updateExtractedIdeas((existingBook.ideas ?? []), source: "conditional refresh")
                } else {
                    print("DEBUG: Ideas unchanged, skipping refresh")
                }
            }
        } catch {
            print("DEBUG: Error checking if refresh needed: \(error)")
        }
    }
    
    // Method to try to extract author from context when initial extraction fails
    private func tryExtractAuthorFromContext(bookTitle: String) async {
        do {
            let systemPrompt = """
            You are an expert at identifying book authors from context.
            
            TASK:
            Based on the book title and the ideas extracted from it, identify the most likely author of the book.
            
            Return ONLY the author name or null, nothing else.
            """
            let ideasBulleted = self.extractedIdeas.prefix(5).map { "- \($0.title): \($0.ideaDescription)" }.joined(separator: "\n")
            let userPrompt = """
            BOOK TITLE: "\(bookTitle)"
            
            EXTRACTED IDEAS:
            \(ideasBulleted)
            
            Who is the most likely author of this book based on the ideas?
            """

            let content = try await openAIService.chat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                model: "gpt-4.1-mini",
                temperature: 0.1,
                maxTokens: 100
            )

            let authorName = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !authorName.isEmpty && authorName.lowercased() != "null" && authorName.lowercased() != "unknown" {
                logger.debug("Identified author from context: \(authorName)")
                await MainActor.run { self.bookInfo = BookInfo(title: bookTitle, author: authorName) }
                do { try bookService.updateBookAuthor(title: bookTitle, author: authorName) }
                catch { logger.error("Failed to update book author: \(String(describing: error))") }
            } else {
                logger.debug("Could not identify author from context")
            }
        } catch {
            logger.error("Error extracting author from context: \(String(describing: error))")
        }
    }
}
