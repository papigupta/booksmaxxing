import SwiftUI
import SwiftData

struct OnboardingView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @State private var bookTitle: String = ""
    @State private var savedBooks: [Book] = []
    @State private var isLoadingSavedBooks = false
    
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
            
            // Input Field
            TextField("Book title and author name", text: $bookTitle)
                .dsTextField()
            
            // Add Button
            Button(action: addNewBook) {
                HStack {
                    Text("Add Book")
                    Spacer()
                    DSIcon("arrow.right", size: 14)
                }
            }
            .dsPrimaryButton()
            .disabled(bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(.easeInOut(duration: 0.2), value: bookTitle)
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
    private func addNewBook() {
        let trimmedTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        bookTitle = ""
        
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Use NavigationState to navigate with eager book creation to fix navigation race condition
        navigationState.navigateToBookWithEagerCreation(title: trimmedTitle, modelContext: modelContext)
    }
    
    private func selectSavedBook(_ book: Book) {
        // Update book's last accessed time
        book.lastAccessed = Date()
        try? modelContext.save()
        
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
