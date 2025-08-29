import SwiftUI
import SwiftData

/// Global navigation state for managing app-wide navigation
class NavigationState: ObservableObject {
    @Published var shouldShowBookSelection = false
    @Published var selectedBookTitle: String? = nil
    
    func navigateToBookSelection() {
        shouldShowBookSelection = true
    }
    
    func navigateToBook(title: String) {
        selectedBookTitle = title
        shouldShowBookSelection = false
    }
    
    func navigateToBookWithEagerCreation(title: String, modelContext: ModelContext) {
        // Create a minimal book record immediately to fix navigation race condition
        Task { @MainActor in
            do {
                let bookService = BookService(modelContext: modelContext)
                
                // This will either find existing book or create new one
                let _ = try bookService.findOrCreateBook(title: title, author: nil)
                print("DEBUG: Ensured book record exists for '\(title)' to enable navigation")
                
                // Now navigate
                selectedBookTitle = title
                shouldShowBookSelection = false
                
            } catch {
                print("ERROR: Failed to ensure book for navigation: \(error)")
                // Fall back to regular navigation
                selectedBookTitle = title
                shouldShowBookSelection = false
            }
        }
    }
    
    func reset() {
        shouldShowBookSelection = false
        selectedBookTitle = nil
    }
}