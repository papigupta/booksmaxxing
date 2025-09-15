import SwiftUI
import SwiftData

struct MainView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var streakManager: StreakManager
    @Query(sort: \Book.lastAccessed, order: .reverse) private var books: [Book]
    
    var body: some View {
        Group {
            if books.isEmpty || navigationState.shouldShowBookSelection {
                // Show OnboardingView which has its own NavigationStack
                OnboardingView(openAIService: openAIService)
                    .environmentObject(navigationState)
                    .onAppear {
                        // Run migration for existing data and cleanup duplicates
                        Task {
                            do {
                                let bookService = BookService(modelContext: modelContext)
                                try await bookService.migrateExistingDataToBookSpecificIds()
                                // Clean up any duplicate books (0 ideas books with similar titles)
                                try bookService.cleanupDuplicateBooks()
                            } catch {
                                print("DEBUG: Migration/cleanup failed: \(error)")
                            }
                        }
                    }
            } else {
                // Wrap BookOverviewView in NavigationStack since it needs navigation context
                NavigationStack {
                    BookOverviewView(
                        bookTitle: navigationState.selectedBookTitle ?? books[0].title,
                        openAIService: openAIService,
                        bookService: BookService(modelContext: modelContext)
                    )
                    .environmentObject(navigationState)
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .onChange(of: books) { oldBooks, newBooks in
            // If we get books and haven't selected one, select the most recent
            if !newBooks.isEmpty && navigationState.selectedBookTitle == nil {
                navigationState.selectedBookTitle = newBooks[0].title
            }
        }
        .onAppear {
            // Initialize selected book on first appear
            if !books.isEmpty && navigationState.selectedBookTitle == nil {
                navigationState.selectedBookTitle = books[0].title
            }
            
            // Run cleanup on app startup for all users
            Task {
                do {
                    let bookService = BookService(modelContext: modelContext)
                    try bookService.cleanupDuplicateBooks()
                    print("DEBUG: Cleaned up duplicate books on app startup")
                } catch {
                    print("DEBUG: Cleanup failed: \(error)")
                }
            }

            // Attach model context to streak manager for SwiftData-backed persistence
            streakManager.attachModelContext(modelContext)

            // Warm CloudKit-backed fetches right after app becomes active
            CloudSyncRefresh(modelContext: modelContext).warmFetches()
        }
    }
}