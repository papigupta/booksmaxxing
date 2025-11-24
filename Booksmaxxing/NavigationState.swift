import SwiftUI
import SwiftData

/// Global navigation state for managing app-wide navigation
class NavigationState: ObservableObject {
    @Published var shouldShowBookSelection = false
    @Published var selectedBookTitle: String? = nil
    @Published var selectedBookID: UUID? = nil
    
    func navigateToBookSelection() {
        shouldShowBookSelection = true
    }
    
    func navigateToBook(_ book: Book) {
        selectedBookID = book.id
        selectedBookTitle = book.title
        shouldShowBookSelection = false
    }
    
    func navigateToBookWithEagerCreation(title: String, modelContext: ModelContext) {
        // Create a minimal book record immediately to fix navigation race condition
        Task { @MainActor in
            do {
                let bookService = BookService(modelContext: modelContext)
                
                // This will either find existing book or create new one
                let created = try bookService.findOrCreateBook(title: title, author: nil)
                print("DEBUG: Ensured book record exists for '\(title)' to enable navigation")
                
                // Now navigate
                navigateToBook(created)
                
            } catch {
                print("ERROR: Failed to ensure book for navigation: \(error)")
                // Fall back to regular navigation
                selectedBookTitle = title
                shouldShowBookSelection = false
                selectedBookID = nil
            }
        }
    }
    
    func reset() {
        shouldShowBookSelection = false
        selectedBookTitle = nil
        selectedBookID = nil
    }
}
