import SwiftUI

/// Cmd+K-style overlay for quickly adding a book.
/// - Presents a focused search field with a blurred, dimmed background.
/// - Reuses GoogleBooksService to fetch suggestions (capped via `maxResults`).
/// - Delegates selection back to the host view.
struct AddBookOverlay: View {
    @Binding var isPresented: Bool
    let maxResults: Int
    let onSelect: (BookMetadata) -> Void

    // Matched geometry to morph from the host “+” button
    let matchedId: String
    let namespace: Namespace.ID

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var query: String = ""
    @State private var results: [BookMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private let googleBooks = GoogleBooksService.shared

    var body: some View {
        ZStack {
            // Backdrop blur + dim
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.18))
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                // Search bar (morph target)
                searchBar
                    .padding(.horizontal, 24)

                contentArea
            }
            .padding(.top, 32)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear { isFocused = true }
        .onDisappear { searchTask?.cancel() }
        .transition(.opacity)
    }

    private var searchBar: some View {
        let palette = themeManager.activeRoles
        let stroke = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray300
        let fill = Color.white.opacity(0.58)
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(palette.color(role: .primary, tone: 40) ?? DS.Colors.secondaryText)

            TextField("Search books", text: $query)
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .font(DS.Typography.fraunces(size: 16, weight: .regular))
                .onChange(of: query) { _, new in scheduleSearch(for: new) }

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fill)
                .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stroke.opacity(0.9), lineWidth: 1.6)
        )
        .matchedGeometryEffect(id: matchedId, in: namespace)
    }

    @ViewBuilder
    private var contentArea: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            copyGuidelines
                .padding(.horizontal, 32)
        } else {
            resultsList
        }
    }

    private var copyGuidelines: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark")
                    .foregroundColor(themeManager.activeRoles.color(role: .primary, tone: 40) ?? DS.Colors.primaryText)
                    .font(.system(size: 14, weight: .semibold))
                Text("Works best with big‑idea non‑fiction books. ")
                    .font(DS.Typography.fraunces(size: 14, weight: .regular))
                    .foregroundColor(DS.Colors.primaryText)
                + Text("Black Swan, Atomic Habits, Sapiens.")
                    .italic()
                    .foregroundColor(DS.Colors.primaryText)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark")
                    .foregroundColor(DS.Colors.destructive)
                    .font(.system(size: 14, weight: .semibold))
                Text("Avoid books that are story‑driven — fiction, biographies, memoirs. ")
                    .font(DS.Typography.fraunces(size: 14, weight: .regular))
                    .foregroundColor(DS.Colors.primaryText)
                + Text("The Great Gatsby, Steve Jobs, Shoe Dog")
                    .italic()
                    .foregroundColor(DS.Colors.primaryText)
            }

            Text("Type at least 3 characters to see suggestions.")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.secondaryText)
                .padding(.top, 8)
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading { ProgressView().padding(.top, 24) }
            if let errorMessage { Text(errorMessage).font(DS.Typography.caption).foregroundColor(DS.Colors.destructive) }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(results.prefix(maxResults)) { book in
                        Button { onSelectAndDismiss(book) } label: {
                            HStack(alignment: .top, spacing: 16) {
                                AsyncImage(url: URL(string: book.thumbnailUrl ?? book.coverImageUrl ?? "")) { phase in
                                    switch phase {
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(DS.Colors.secondaryBackground)
                                            .frame(width: 56, height: 84)
                                            .overlay { ProgressView() }
                                    case .success(let image):
                                        image.resizable().scaledToFill().frame(width: 56, height: 84).clipped().cornerRadius(8)
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(DS.Colors.secondaryBackground)
                                            .frame(width: 56, height: 84)
                                            .overlay { Image(systemName: "book").foregroundColor(DS.Colors.secondaryText) }
                                    @unknown default: EmptyView()
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Actions
    private func dismiss() { withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { isPresented = false } }

    private func onSelectAndDismiss(_ metadata: BookMetadata) {
        onSelect(metadata)
        dismiss()
    }

    private func scheduleSearch(for raw: String) {
        searchTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await MainActor.run { isLoading = true; errorMessage = nil }
            do {
                let response = try await googleBooks.searchBooks(query: trimmed, maxResults: maxResults)
                if Task.isCancelled { return }
                await MainActor.run { results = response; isLoading = false; if response.isEmpty { errorMessage = "No books found. Try another query." } }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { results = []; isLoading = false; errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
    }
}
