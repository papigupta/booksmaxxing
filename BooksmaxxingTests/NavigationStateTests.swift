import Testing
@testable import Booksmaxxing

@MainActor
struct NavigationStateTests {
    @Test
    func navigateToBookSelectionTogglesFlag() {
        let nav = NavigationState()
        nav.selectedBookTitle = "Temp"
        nav.selectedBookID = UUID()
        nav.navigateToBookSelection()
        #expect(nav.shouldShowBookSelection == true)
        #expect(nav.selectedBookTitle == nil)
        #expect(nav.selectedBookID == nil)
    }

    @Test
    func navigateToBookResetsSelectionFlag() {
        let nav = NavigationState()
        let book = Book(title: "Sample")
        nav.shouldShowBookSelection = true
        nav.navigateToBook(book)
        #expect(nav.selectedBookTitle == "Sample")
        #expect(nav.selectedBookID == book.id)
        #expect(nav.shouldShowBookSelection == false)
    }

    @Test
    func resetClearsState() {
        let nav = NavigationState()
        nav.shouldShowBookSelection = true
        nav.selectedBookTitle = "Temp"
        nav.reset()
        #expect(nav.shouldShowBookSelection == false)
        #expect(nav.selectedBookTitle == nil)
    }
}
