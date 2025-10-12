import SwiftUI

/// Shared Google Books search component used for onboarding and experiments.
struct BookSearchView: View {
    let title: String
    let description: String?
    let placeholder: String
    let minimumCharacters: Int
    let selectionHint: String?
    let clearOnSelect: Bool
    // Optional cap for results; defaults to existing behavior elsewhere
    let maxResults: Int?
    let onSelect: (BookMetadata) -> Void

    @State private var searchText: String = ""
    @State private var results: [BookMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let googleBooksService = GoogleBooksService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(DS.Typography.subheadline)
                    .foregroundColor(DS.Colors.primaryText)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                }
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .dsTextField()
                    .onChange(of: searchText) { _, newValue in
                        scheduleSearch(for: newValue)
                    }
            }
            .padding()
            .dsCard()

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.destructive)
                    .padding(.horizontal)
            }

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < minimumCharacters {
                Text("Type at least \(minimumCharacters) characters to see suggestions.")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                    .padding(.horizontal)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }

                    ForEach(results) { book in
                        Button {
                            handleSelection(book)
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                AsyncImage(url: URL(string: book.thumbnailUrl ?? book.coverImageUrl ?? "")) { phase in
                                    switch phase {
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(DS.Colors.secondaryBackground)
                                            .frame(width: 56, height: 84)
                                            .overlay { ProgressView() }
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 56, height: 84)
                                            .clipped()
                                            .cornerRadius(8)
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(DS.Colors.secondaryBackground)
                                            .frame(width: 56, height: 84)
                                            .overlay {
                                                Image(systemName: "book")
                                                    .foregroundColor(DS.Colors.secondaryText)
                                            }
                                    @unknown default:
                                        EmptyView()
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(book.title)
                                        .font(DS.Typography.bodyBold)
                                        .foregroundColor(DS.Colors.primaryText)
                                        .lineLimit(2)

                                    if !book.authors.isEmpty {
                                        Text(book.authors.joined(separator: ", "))
                                            .font(DS.Typography.caption)
                                            .foregroundColor(DS.Colors.secondaryText)
                                            .lineLimit(2)
                                    }

                                    if let subtitle = book.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(DS.Typography.caption)
                                            .foregroundColor(DS.Colors.tertiaryText)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(DS.Colors.secondaryText)
                            }
                            .padding()
                            .dsCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if !isLoading && !results.isEmpty, let selectionHint {
                        Text(selectionHint)
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 16)
        .background(DS.Colors.secondaryBackground)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func handleSelection(_ book: BookMetadata) {
        searchTask?.cancel()
        if clearOnSelect {
            searchText = ""
            results = []
        }
        errorMessage = nil
        onSelect(book)
    }

    private func scheduleSearch(for rawQuery: String) {
        searchTask?.cancel()

        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }

            do {
                let response = try await googleBooksService.searchBooks(
                    query: trimmed,
                    maxResults: maxResults ?? 12
                )
                if Task.isCancelled { return }

                await MainActor.run {
                    results = response
                    isLoading = false
                    if response.isEmpty {
                        errorMessage = "No books found. Try a different title or add more detail."
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    results = []
                    isLoading = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
