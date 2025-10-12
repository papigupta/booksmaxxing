import SwiftUI
import SwiftData

/// Temporary harness that lets us manually seed a small bookshelf and jump into the new BookSelectionView.
struct BookSelectionDevToolsView: View {
    let openAIService: OpenAIService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationState: NavigationState
    @EnvironmentObject private var themeManager: ThemeManager

    @Query(sort: \Book.createdAt, order: .reverse)
    private var allBooks: [Book]

    @State private var isProcessingSelection = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showSelectionPreview = false
    @State private var lastAddedBookId: UUID?

    private var bookService: BookService {
        BookService(modelContext: modelContext)
    }

    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }

    private var bookCapReached: Bool {
        allBooks.count >= 7
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    introSection
                    manualAddSection
                    bookshelfSection
                    previewSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.lg)
            }
            .background(DS.Colors.secondaryBackground)
            .navigationTitle("Book Selection Lab")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showSelectionPreview) {
            BookSelectionView(openAIService: openAIService)
                .environmentObject(navigationState)
                .environmentObject(themeManager)
        }
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Seed up to seven books to test the onboarding carousel.")
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.primaryText)

            Text("Use Google Books search to pick the exact cover you want. The newest book in this list will appear first in the carousel.")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)
        }
    }

    private var manualAddSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                DSIcon("plus.circle.fill", size: 20)
                Text("Add a book via Google Books")
                    .font(DS.Typography.subheadline)
            }
            .foregroundColor(DS.Colors.primaryText)

            if bookCapReached {
                Text("You’ve reached the temporary limit of seven books. Delete one below to add another.")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.destructive)
            }

            BookSearchView(
                title: "Search catalog",
                description: "Pick the exact edition so the cover art matches.",
                placeholder: "Search by title, author, or ISBN",
                minimumCharacters: 3,
                selectionHint: "Tap a result to add it to the carousel",
                clearOnSelect: true,
                maxResults: nil,
                onSelect: addBookFromMetadata
            )
            .disabled(isProcessingSelection || bookCapReached)

            if isProcessingSelection {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text(statusMessage ?? "Adding book…")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                }
            } else if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.destructive)
            }
        }
        .padding()
        .dsCard()
    }

    private var bookshelfSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Current book list")
                    .font(DS.Typography.subheadline)
                Spacer()
                Text("Newest first")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
            }

            ForEach(allBooks.prefix(7)) { book in
                HStack(spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(book.title)
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(DS.Colors.primaryText)
                            .lineLimit(2)
                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        Text(book.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(DS.Typography.small)
                            .foregroundColor(DS.Colors.tertiaryText)
                    }
                    Spacer()
                    Menu {
                        Button("Set as latest") {
                            promoteBook(book)
                        }
                        Button(role: .destructive) {
                            deleteBook(book)
                        } label: {
                            Text("Delete")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(DS.Colors.secondaryText)
                    }
                }
                .padding(.vertical, DS.Spacing.xs)

                Divider()
            }

            if allBooks.isEmpty {
                Text("No books yet. Add six to mirror the production onboarding experience.")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
            }
        }
        .padding()
        .dsCard()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Preview the carousel")
                .font(DS.Typography.subheadline)

            Text("We’ll open the new BookSelection screen using the books above. When you select one, the navigation state is persisted so reopening the app keeps your choice.")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)

            Button(action: { showSelectionPreview = true }) {
                Text("Launch BookSelection")
                    .font(DS.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Colors.black)
                    .foregroundColor(DS.Colors.white)
                    .cornerRadius(12)
            }
            .disabled(allBooks.isEmpty)
        }
        .padding()
        .dsCard()
    }

    private func addBookFromMetadata(_ metadata: BookMetadata) {
        guard !bookCapReached else { return }
        errorMessage = nil
        statusMessage = nil

        Task { @MainActor in
            isProcessingSelection = true
            statusMessage = "Adding \(metadata.title)…"

            do {
                let primaryAuthor = metadata.authors.first
                let book = try bookService.findOrCreateBook(
                    title: metadata.title,
                    author: primaryAuthor,
                    triggerMetadataFetch: false
                )

                bookService.applyMetadata(metadata, to: book)
                book.lastAccessed = Date()
                try modelContext.save()

                lastAddedBookId = book.id
                statusMessage = "Added \(metadata.title)."
                isProcessingSelection = false

                // Precompute theme so the preview is immediate
                Task { await themeManager.activateTheme(for: book) }

                // Kick off idea extraction in background
                let extractionViewModel = IdeaExtractionViewModel(
                    openAIService: openAIService,
                    bookService: bookService
                )
                Task.detached(priority: .background) {
                    await extractionViewModel.loadOrExtractIdeas(from: metadata.title, metadata: metadata)
                }
            } catch {
                isProcessingSelection = false
                statusMessage = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func promoteBook(_ book: Book) {
        book.createdAt = Date()
        book.lastAccessed = Date()
        try? modelContext.save()
    }

    private func deleteBook(_ book: Book) {
        modelContext.delete(book)
        try? modelContext.save()
    }
}

#Preview {
    BookSelectionDevToolsView(openAIService: OpenAIService(apiKey: "demo"))
        .environmentObject(NavigationState())
        .environmentObject(ThemeManager())
}
