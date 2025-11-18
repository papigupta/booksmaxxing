import SwiftUI
import SwiftData
import FirebaseAnalytics

struct MainView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Query(sort: \Book.lastAccessed, order: .reverse) private var books: [Book]

    private var activeBook: Book? {
        if let selectedTitle = navigationState.selectedBookTitle,
           let selectedBook = books.first(where: { $0.title == selectedTitle }) {
            return selectedBook
        }
        return books.first
    }
    
    var body: some View {
        Group {
            if books.isEmpty || navigationState.shouldShowBookSelection {
                // Show OnboardingView which has its own NavigationStack
                OnboardingView(openAIService: openAIService)
                    .environmentObject(navigationState)
            } else if let book = activeBook {
                DailyPracticeHomepage(
                    book: book,
                    openAIService: openAIService,
                    isRootExperience: true
                )
            } else {
                ProgressView("Loading your library…")
            }
        }
        .onChange(of: books) { oldBooks, newBooks in
            // If we get books and haven't selected one, select the most recent
            if !newBooks.isEmpty && navigationState.selectedBookTitle == nil {
                navigationState.selectedBookTitle = newBooks[0].title
            }
        }
        .onAppear {
            Analytics.logEvent("test_event", parameters: nil)
            // Initialize selected book on first appear
            if !books.isEmpty && navigationState.selectedBookTitle == nil {
                navigationState.selectedBookTitle = books[0].title
            }
            
            // Run cleanup on app startup for all users
            Task {
                do {
                    let bookService = BookService(modelContext: modelContext)
                    try await bookService.migrateExistingDataToBookSpecificIds()
                    try bookService.cleanupDuplicateBooks()
                    print("DEBUG: Completed migration and duplicate cleanup on app startup")
                } catch {
                    print("DEBUG: Migration/cleanup failed: \(error)")
                }
            }

            // Attach model context to streak manager for SwiftData-backed persistence
            streakManager.attachModelContext(modelContext)
            // Attach to theme manager as well
            themeManager.attachModelContext(modelContext)

            // Warm CloudKit-backed fetches right after app becomes active
            CloudSyncRefresh(modelContext: modelContext).warmFetches()
        }
    }
}
