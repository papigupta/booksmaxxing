import SwiftUI
import SwiftData

struct OnboardingView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @State private var bookTitle: String = ""
    @State private var savedBooks: [Book] = []
    @State private var isLoadingSavedBooks = false
    @State private var isNavigatingToBookOverview = false
    @State private var selectedBookTitle: String = ""
    @State private var selectedSavedBook: Book?
    
    private var bookService: BookService {
        BookService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header Section
                    headerSection
                    
                    // Add New Book Section
                    addNewBookSection
                    
                    // Continue with Saved Book Section
                    savedBooksSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Deepread")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $isNavigatingToBookOverview) {
                if let savedBook = selectedSavedBook {
                    BookOverviewView(
                        bookTitle: savedBook.title, 
                        openAIService: openAIService, 
                        bookService: bookService
                    )
                } else {
                    BookOverviewView(
                        bookTitle: selectedBookTitle, 
                        openAIService: openAIService, 
                        bookService: bookService
                    )
                }
            }
            .onAppear {
                loadSavedBooks()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Which book do you want to master?")
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Add New Book Section
    private var addNewBookSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Add New Book")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            // Input Field
            TextField("Book title and author name", text: $bookTitle)
                .textFieldStyle(.roundedBorder)
                .font(.body)
            
            // Add Button
            Button(action: addNewBook) {
                HStack {
                    Text("Add Book")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(.easeInOut(duration: 0.2), value: bookTitle)
        }
    }
    
    // MARK: - Saved Books Section
    private var savedBooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: "book.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                Text("Continue with Saved Book")
                    .font(.headline)
                    .fontWeight(.semibold)
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
                .scaleEffect(0.8)
            Text("Loading your books...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No saved books yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Add your first book above to get started")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var savedBooksList: some View {
        LazyVStack(spacing: 12) {
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
        
        selectedBookTitle = trimmedTitle
        selectedSavedBook = nil
        bookTitle = ""
        
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        isNavigatingToBookOverview = true
    }
    
    private func selectSavedBook(_ book: Book) {
        selectedSavedBook = book
        selectedBookTitle = ""
        isNavigatingToBookOverview = true
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let author = book.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        Text("\(book.ideas.count) ideas")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(book.lastAccessed.timeAgoDisplay())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
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
