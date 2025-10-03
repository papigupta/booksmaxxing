import SwiftUI
import SwiftData

struct OnboardingView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var themeManager: ThemeManager
    @State private var savedBooks: [Book] = []
    @State private var isLoadingSavedBooks = false
    @State private var isProcessingSelection = false
    @State private var selectionError: String?
    @State private var selectionStatus: String?
    @State private var selectionTask: Task<Void, Never>?
    @State private var extractionTask: Task<Void, Never>?
    
    private var bookService: BookService {
        BookService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    // Header Section
                    headerSection
                    
                    // Add New Book Section
                    addNewBookSection

                    // Continue with Saved Book Section
                    savedBooksSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)
            }
            .navigationBarHidden(true)
            .onAppear {
                loadSavedBooks()
            }
            .onDisappear {
                selectionTask?.cancel()
                extractionTask?.cancel()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: DS.Spacing.md) {
            // Streak in top-right
            HStack {
                Spacer()
                StreakIndicatorView()
            }
            // App branding
            VStack(spacing: DS.Spacing.xs) {
                Text("Booksmaxxing")
                    .font(.custom("Fraunces", size: 24).bold().italic())
                    .tracking(DS.Typography.tightTracking(for: 24))
                    .foregroundColor(DS.Colors.primaryText)
                
                Text("Books don't owe you knowledge, you owe them work.")
                    .font(DS.Typography.fraunces(size: 14, weight: .light))
                    .tracking(DS.Typography.tightTracking(for: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Colors.secondaryText)
                    .padding(.horizontal, DS.Spacing.sm)
            }
            
            // Divider
            Rectangle()
                .fill(DS.Colors.tertiaryText.opacity(0.3))
                .frame(height: 1)
                .frame(maxWidth: 120)
            
        }
        .padding(.top, DS.Spacing.sm)
    }
    
    // MARK: - Add New Book Section
    private var addNewBookSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Section Header
            HStack {
                DSIcon("plus.circle.fill", size: 24)
                Text("Which non-fic book do you want to master?")
                    .font(DS.Typography.headline)
            }

            Text("Use search to auto-fill from Google Books. We'll start extracting ideas instantly once you pick a match.")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)

            BookSearchView(
                title: "Find your book",
                description: nil,
                placeholder: "Search by title, author, or ISBN",
                minimumCharacters: 3,
                selectionHint: "Tap a result to begin extracting ideas.",
                clearOnSelect: true,
                onSelect: handleBookSelection
            )
            .disabled(isProcessingSelection)

            if isProcessingSelection {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(selectionStatus ?? "Extracting ideas…")
                        .font(DS.Typography.caption)
                }
                .padding(.horizontal, DS.Spacing.sm)
            }

            if let selectionError {
                Text(selectionError)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.destructive)
                    .padding(.horizontal, DS.Spacing.sm)
            }
        }
    }
    
    // MARK: - Saved Books Section
    private var savedBooksSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Section Header
            HStack {
                DSIcon("book.circle.fill", size: 24)
                Text("Continue with Saved Book")
                    .font(DS.Typography.headline)
            }
            
            // Books List
            if isLoadingSavedBooks {
                loadingView
            } else if savedBooks.isEmpty {
                emptyStateView
            } else {
                savedBooksList
            }
        }
    }
    
    // MARK: - Supporting Views
    private var loadingView: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                .scaleEffect(0.8)
            Text("Loading your books...")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.xs)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSIcon("book.closed", size: 32)
            Text("No saved books yet")
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.secondaryText)
            Text("Add your first book above to get started")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
    }
    
    private var savedBooksList: some View {
        LazyVStack(spacing: DS.Spacing.sm) {
            ForEach(savedBooks.sorted(by: { $0.lastAccessed > $1.lastAccessed })) { book in
                SavedBookCard(book: book) {
                    selectSavedBook(book)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: savedBooks.count)
    }
    
    // MARK: - Action Handlers
    private func selectSavedBook(_ book: Book) {
        // Update book's last accessed time
        book.lastAccessed = Date()
        try? modelContext.save()
        
        // Activate per-book theme immediately before navigating
        Task { await themeManager.activateTheme(for: book) }
        
        // Use NavigationState to navigate
        navigationState.navigateToBook(title: book.title)
    }
    
    private func loadSavedBooks() {
        isLoadingSavedBooks = true
        Task {
            do {
                let books = try bookService.getAllBooks()
                await MainActor.run {
                    self.savedBooks = books
                    self.isLoadingSavedBooks = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSavedBooks = false
                }
            }
        }
    }

    private func handleBookSelection(_ metadata: BookMetadata) {
        selectionTask?.cancel()
        extractionTask?.cancel()
        selectionTask = Task { @MainActor in
            isProcessingSelection = true
            selectionError = nil
            selectionStatus = "Preparing \(metadata.title)…"

            do {
                let primaryAuthor = metadata.authors.first
                let book = try bookService.findOrCreateBook(
                    title: metadata.title,
                    author: primaryAuthor,
                    triggerMetadataFetch: false
                )

                book.lastAccessed = Date()
                bookService.applyMetadata(metadata, to: book)

                selectionStatus = "Extracting ideas…"

                Task { await themeManager.activateTheme(for: book) }

                let extractionViewModel = IdeaExtractionViewModel(
                    openAIService: openAIService,
                    bookService: bookService
                )
                extractionTask = Task { @MainActor in
                    await extractionViewModel.loadOrExtractIdeas(from: metadata.title, metadata: metadata)
                    extractionTask = nil
                }

                navigationState.navigateToBook(title: book.title)
                selectionStatus = nil
                isProcessingSelection = false
                selectionTask = nil
            } catch is CancellationError {
                selectionStatus = nil
                selectionError = nil
                isProcessingSelection = false
                selectionTask = nil
            } catch {
                selectionStatus = nil
                selectionError = error.localizedDescription
                isProcessingSelection = false
                selectionTask = nil
            }
        }
    }
}

// MARK: - Saved Book Card
struct SavedBookCard: View {
    let book: Book
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(book.title)
                        .font(DS.Typography.bodyBold)
                        .foregroundColor(DS.Colors.primaryText)
                        .lineLimit(2)
                    
                    if let author = book.author {
                        Text(author)
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: DS.Spacing.xs) {
                        Text("\((book.ideas ?? []).count) ideas")
                            .font(DS.Typography.small)
                            .foregroundColor(DS.Colors.tertiaryText)
                        
                        Text("•")
                            .font(DS.Typography.small)
                            .foregroundColor(DS.Colors.tertiaryText)
                        
                        Text(book.lastAccessed.timeAgoDisplay())
                            .font(DS.Typography.small)
                            .foregroundColor(DS.Colors.tertiaryText)
                    }
                }
                
                Spacer()
                
                DSIcon("chevron.right", size: 12)
            }
            .dsCard()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Time Ago Extension
extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
