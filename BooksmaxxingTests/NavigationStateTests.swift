import Testing
@testable import Booksmaxxing

@MainActor
struct NavigationStateTests {
    @Test
    func navigateToBookSelectionTogglesFlag() {
        let nav = NavigationState()
        nav.navigateToBookSelection()
        #expect(nav.shouldShowBookSelection == true)
    }

    @Test
    func navigateToBookResetsSelectionFlag() {
        let nav = NavigationState()
        nav.shouldShowBookSelection = true
        nav.navigateToBook(title: "Sample")
        #expect(nav.selectedBookTitle == "Sample")
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
