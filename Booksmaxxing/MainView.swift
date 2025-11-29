import SwiftUI
import SwiftData

struct MainView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Query(sort: \Book.lastAccessed, order: .reverse) private var books: [Book]
    @State private var hasTrackedAppOpen = false
    @State private var hasAttemptedStarterSeed = false
    @State private var userProfile: UserProfile?
    @State private var starterSeedAttempts = 0
    @State private var starterSeedErrorMessage: String?

    private let maxStarterSeedAttempts = 3

    private var activeBook: Book? {
        if let selectedID = navigationState.selectedBookID,
           let book = books.first(where: { $0.id == selectedID }) {
            return book
        }
        if let selectedTitle = navigationState.selectedBookTitle,
           let selectedBook = books.first(where: { $0.title == selectedTitle }) {
            return selectedBook
        }
        return nil
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
                .id(book.id)
            } else {
                ProgressView("Loading your library…")
            }
        }
        .alert(
            "Starter Library Issue",
            isPresented: Binding(
                get: { starterSeedErrorMessage != nil },
                set: { if !$0 { starterSeedErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { starterSeedErrorMessage = nil }
        } message: {
            Text(starterSeedErrorMessage ?? "")
        }
        .onChange(of: books) { _, newBooks in
            if let profile = userProfile {
                updateNavigationState(for: profile, books: newBooks)
            }
        }
        .onChange(of: navigationState.selectedBookID) { _, newID in
            guard let newID, let book = books.first(where: { $0.id == newID }) else { return }
            persistSelectedBook(book: book)
        }
        .onAppear {
            if !hasTrackedAppOpen {
                AnalyticsManager.shared.track(.appOpened)
                hasTrackedAppOpen = true
            }
            // Initialize selected book on first appear
            if let first = books.first, navigationState.selectedBookID == nil {
                navigationState.selectedBookID = first.id
                navigationState.selectedBookTitle = first.title
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

            if !hasAttemptedStarterSeed {
                hasAttemptedStarterSeed = true
                Task { @MainActor in
                    await seedStarterLibraryIfNeeded()
                }
            }

            Task { @MainActor in
                do {
                    let profile = try ensureUserProfile()
                    self.userProfile = profile
                    updateNavigationState(for: profile, books: books)
                } catch {
                    print("DEBUG: Failed to load user profile: \(error)")
                }
            }
        }
    }
}

// MARK: - Starter Library Support
extension MainView {
    @MainActor
    private func seedStarterLibraryIfNeeded(retryAttempt: Int = 1) async {
        starterSeedAttempts = retryAttempt
        do {
            let profile = try ensureUserProfile()
            self.userProfile = profile
            let currentVersion = StarterLibrary.currentVersion
            guard profile.starterLibraryVersion < currentVersion else { return }

            // If books already exist with ideas, assume seeding happened previously even if the profile flag wasn't set
            let hasExistingLibrary = books.contains { ($0.ideas ?? []).isEmpty == false }
            if hasExistingLibrary {
                profile.starterLibraryVersion = currentVersion
                profile.updatedAt = Date.now
                try modelContext.save()
                updateNavigationState(for: profile, books: books)
                return
            }

            let seeder = StarterBookSeeder(modelContext: modelContext)
            let seededCount = try seeder.seedAllBooksIfNeeded()
            if seededCount > 0 {
                AnalyticsManager.shared.track(.starterLibrarySeeded(bookCount: seededCount))
            }
            profile.starterLibraryVersion = currentVersion
            profile.updatedAt = Date.now
            try modelContext.save()
            updateNavigationState(for: profile, books: books)
        } catch {
            print("DEBUG: Starter library seeding attempt \(retryAttempt) failed: \(error)")
            AnalyticsManager.shared.track(
                .starterLibrarySeedingFailed(
                    reason: "Attempt \(retryAttempt) of \(maxStarterSeedAttempts): \(error.localizedDescription)"
                )
            )
            if retryAttempt < maxStarterSeedAttempts {
                let delay = UInt64(Double(retryAttempt) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                await seedStarterLibraryIfNeeded(retryAttempt: retryAttempt + 1)
            } else {
                starterSeedErrorMessage = "We couldn't load the starter library. Please relaunch or add a book manually. (\(error.localizedDescription))"
            }
        }
    }

    @MainActor
    private func ensureUserProfile() throws -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let profiles = try modelContext.fetch(descriptor)
        if let existing = profiles.first {
            if profiles.count > 1 {
                // Ensure there's only a single profile record going forward
                for extra in profiles.dropFirst() {
                    modelContext.delete(extra)
                }
                try modelContext.save()
            }
            self.userProfile = existing
            return existing
        }

        let profile = UserProfile()
        modelContext.insert(profile)
        try modelContext.save()
        self.userProfile = profile
        return profile
    }

    @MainActor
    private func updateNavigationState(for profile: UserProfile, books: [Book]) {
        if navigationState.shouldShowBookSelection {
            return
        }

        if let currentID = navigationState.selectedBookID,
           books.contains(where: { $0.id == currentID }) {
            return
        }

        if !profile.hasCompletedInitialBookSelection {
            navigationState.shouldShowBookSelection = true
            navigationState.selectedBookTitle = nil
            navigationState.selectedBookID = nil
            return
        }

        navigationState.shouldShowBookSelection = false

        if let savedTitle = profile.lastOpenedBookTitle,
           let savedBook = books.first(where: { $0.title == savedTitle }) {
            navigationState.selectedBookID = savedBook.id
            navigationState.selectedBookTitle = savedBook.title
        } else if navigationState.selectedBookID == nil, let first = books.first {
            navigationState.selectedBookID = first.id
            navigationState.selectedBookTitle = first.title
        }
    }

    @MainActor
    private func persistSelectedBook(book: Book) {
        do {
            let profile = try ensureUserProfile()
            profile.lastOpenedBookTitle = book.title
            if !profile.hasCompletedInitialBookSelection {
                profile.hasCompletedInitialBookSelection = true
            }
            profile.updatedAt = Date.now
            try modelContext.save()
            self.userProfile = profile
        } catch {
            print("DEBUG: Failed to persist selected book: \(error)")
        }
    }
}
