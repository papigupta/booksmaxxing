import SwiftUI
import SwiftData

struct MainView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @Query(sort: \Book.lastAccessed, order: .reverse) private var books: [Book]
    
    var body: some View {
        Group {
            if books.isEmpty || navigationState.shouldShowBookSelection {
                // Show OnboardingView which has its own NavigationStack
                OnboardingView(openAIService: openAIService)
                    .environmentObject(navigationState)
                    .onAppear {
                        // Run migration for existing data
                        Task {
                            do {
                                let bookService = BookService(modelContext: modelContext)
                                try await bookService.migrateExistingDataToBookSpecificIds()
                            } catch {
                                print("DEBUG: Migration failed: \(error)")
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
        }
    }
}