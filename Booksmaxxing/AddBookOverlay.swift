import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var guidelinesVisible: Bool = false
    @State private var dockedToTop: Bool = false
    @State private var searchBarHeight: CGFloat = 48
    private let dockAdditionalOffset: CGFloat = 40 // fine‑tune docked position under notch
    @State private var keyboardHeight: CGFloat = 0
    private let bottomGapAboveKeyboard: CGFloat = 2 // tweakable gap between last result and keyboard

    private let googleBooks = GoogleBooksService.shared

    // Fallback top safe-area using UIKit in case SwiftUI reports 0 insets in certain overlays
    private var uiTopSafeInset: CGFloat {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
        for scene in scenes {
            if let winScene = scene as? UIWindowScene {
                if let key = winScene.windows.first(where: { $0.isKeyWindow }) {
                    let top = key.safeAreaInsets.top
                    if top > 0 { return top }
                }
                // Take max as a fallback across windows
                let top = winScene.windows.map { $0.safeAreaInsets.top }.max() ?? 0
                if top > 0 { return top }
            }
        }
        return 44 // sensible default for notched iPhones
        #else
        return 0
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let size = proxy.size
            let dockTop: CGFloat = max(safeTop, uiTopSafeInset) + 12 + dockAdditionalOffset
            let centerTop: CGFloat = max((size.height - searchBarHeight) / 2, dockTop)
            let top: CGFloat = dockedToTop ? dockTop : centerTop

            ZStack(alignment: .topLeading) {
                // Backdrop blur + dim (covers whole screen)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.18))
                    .onTapGesture { dismiss() }

                // Single persistent search bar – moved via position (keeps identity and focus)
                searchBar
                    .padding(.horizontal, 24)
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: top + searchBarHeight / 2)

                // Content below the bar: guidelines or results, anchored beneath it
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                    copyGuidelines
                        .padding(.horizontal, 24)
                        .opacity(guidelinesVisible ? 1.0 : 0.0)
                        .offset(y: guidelinesVisible ? 0 : 8)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .position(x: size.width / 2, y: top + searchBarHeight + 8 + 60)
                } else {
                    VStack { contentArea }
                        .padding(.top, top + searchBarHeight + 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            // Allow keyboard to adjust layout so the centered field nudges upward slightly
        }
        .onAppear {
            // Hard reset to guarantee initial centered state
            query = ""
            results = []
            errorMessage = nil
            dockedToTop = false
            guidelinesVisible = false
            // Delay keyboard to let the overlay settle visually
            Task { @MainActor in
                // Wait for morph + helper fade to complete before focusing to show keyboard
                try? await Task.sleep(nanoseconds: 460_000_000)
                withAnimation(.easeIn(duration: 0.15)) { isFocused = true }
            }
            // Stagger guidelines after the search bar morph completes
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                withAnimation(.easeOut(duration: 0.28)) { guidelinesVisible = true }
            }
        }
        .onDisappear { searchTask?.cancel() }
        .transition(.opacity)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notif in
            #if canImport(UIKit)
            guard let info = notif.userInfo,
                  let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow
            else { return }
            let screenHeight = window.bounds.height
            let overlap = max(0, screenHeight - endFrame.origin.y)
            keyboardHeight = overlap
            #endif
        }
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
                .onChange(of: query) { _, new in
                    scheduleSearch(for: new)
                    // One-way docking: once user starts typing, dock under notch and keep it there
                    if !dockedToTop {
                        let hasTyped = !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if hasTyped {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                                dockedToTop = true
                            }
                        }
                    }
                }

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
        .overlay(
            GeometryReader { g in
                Color.clear
                    .onAppear { searchBarHeight = g.size.height }
                    .onChange(of: g.size.height) { _, new in searchBarHeight = new }
            }
        )
        .matchedGeometryEffect(id: matchedId, in: namespace)
    }

    @ViewBuilder
    private var contentArea: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            copyGuidelines
                .padding(.horizontal, 32)
                .opacity(guidelinesVisible ? 1.0 : 0.0)
                .offset(y: guidelinesVisible ? 0 : 8)
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
                (
                    Text("Works best with big‑idea non‑fiction books. ")
                        .font(DS.Typography.fraunces(size: 14, weight: .regular))
                        .foregroundColor(DS.Colors.primaryText)
                    + Text("Black Swan, Atomic Habits, Sapiens.")
                        .font(DS.Typography.frauncesItalic(size: 14, weight: .regular))
                        .foregroundColor(DS.Colors.primaryText)
                )
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark")
                    .foregroundColor(DS.Colors.primaryText)
                    .font(.system(size: 14, weight: .semibold))
                (
                    Text("Avoid books that are story‑driven — fiction, biographies, memoirs. ")
                        .font(DS.Typography.fraunces(size: 14, weight: .regular))
                        .foregroundColor(DS.Colors.primaryText)
                    + Text("The Great Gatsby, Steve Jobs, Shoe Dog")
                        .font(DS.Typography.frauncesItalic(size: 14, weight: .regular))
                        .foregroundColor(DS.Colors.primaryText)
                )
            }
        }
    }

    private var resultsList: some View {
        let palette = themeManager.activeRoles
        let stroke = palette.color(role: .primary, tone: 80) ?? DS.Colors.gray300
        let fill = Color.white.opacity(0.58)

        return Group {
            if isLoading && results.isEmpty {
                VStack { ProgressView().scaleEffect(1.1) }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let errorMessage { Text(errorMessage).font(DS.Typography.caption).foregroundColor(DS.Colors.destructive) }

                        ForEach(results.prefix(maxResults)) { book in
                            Button { onSelectAndDismiss(book) } label: {
                                HStack(alignment: .top, spacing: 16) {
                                    BookCoverView(
                                        thumbnailUrl: book.thumbnailUrl,
                                        coverUrl: book.coverImageUrl,
                                        isLargeView: false,
                                        cornerRadius: 8,
                                        targetSize: CGSize(width: 56, height: 84)
                                    )

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

                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DS.Colors.secondaryText)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(fill)
                                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(stroke.opacity(0.9), lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, keyboardHeight + bottomGapAboveKeyboard)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
    }

    // MARK: - Actions
    private func dismiss() {
        // Close keyboard first, then animate overlay dismissal
        Task { @MainActor in
            let hadFocus = isFocused
            if hadFocus {
                isFocused = false
                // Give the keyboard time to retract before overlay animates away
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                isPresented = false
            }
        }
    }

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
                await MainActor.run {
                    results = response
                    isLoading = false
                    if response.isEmpty {
                        errorMessage = "No books found. Try another query."
                    } else {
                        // Prefetch thumbnails for snappier UI
                        for b in response {
                            if let t = b.thumbnailUrl {
                                ImageCache.shared.prefetch(urlString: t, targetSize: CGSize(width: 56, height: 84))
                            }
                        }
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { results = []; isLoading = false; errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
    }
}
