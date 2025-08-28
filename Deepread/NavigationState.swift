import SwiftUI

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
    
    func reset() {
        shouldShowBookSelection = false
        selectedBookTitle = nil
    }
}