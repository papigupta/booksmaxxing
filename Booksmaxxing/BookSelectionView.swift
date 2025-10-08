import SwiftUI
import SwiftData

struct BookSelectionView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Book.createdAt, order: .reverse)
    private var allBooks: [Book]

    @State private var selectedIndex: Int = 0
    @State private var isProcessingSelection = false
    @State private var selectionStatus: String?
    @State private var selectionError: String?
    @State private var animateIn = false
    @State private var showSearchSheet = false

    private let addButtonDiameter: CGFloat = 52
    private let addButtonGap: CGFloat = 12
    // Prevent layout jumping: fix heights for title, author, and details block
    private let titleAuthorBlockHeight: CGFloat = 72 // fits 2-line title + 1-line author + 4pt gap
    private let detailsFixedHeight: CGFloat = 140 // description + stats area
    // Dots positioning and carousel offset to avoid overlap
    private let dotsTop: CGFloat = 40
    private let dotRowHeight: CGFloat = 12
    private let dotCarouselGap: CGFloat = 0
    private var carouselTopOffset: CGFloat { dotsTop + dotRowHeight + dotCarouselGap }

    private var bookService: BookService {
        BookService(modelContext: modelContext)
    }

    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }

    private var carouselBooks: [Book] {
        Array(allBooks.prefix(6))
    }

    private var activeBook: Book? {
        guard !carouselBooks.isEmpty, selectedIndex < carouselBooks.count else { return nil }
        return carouselBooks[selectedIndex]
    }

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                Spacer(minLength: carouselTopOffset)

                carouselSection
                    .frame(height: 320)
                    .padding(.bottom, 0)

                bookDetailSection
                    .padding(.top, 32)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                let safeBottom = proxy.safeAreaInsets.bottom + 0
                ZStack {
                    // Centered primary CTA
                    selectButtonControl
                        .shadow(color: themeManager.currentTokens(for: colorScheme).primary.opacity(0.22), radius: 22, x: 0, y: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, safeBottom)

                    // Trailing plus FAB
                    HStack { Spacer(); addBookButton }
                        .padding(.trailing, 32)
                        .padding(.bottom, safeBottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            dotsSection
                .padding(.top, dotsTop)
                .allowsHitTesting(false)
        }
        .onAppear { handleInitialAppear() }
        .onChange(of: carouselBooks.count) { _, _ in adjustSelectionForBookChanges() }
        .onChange(of: selectedIndex) { _, newValue in handleSelectionChange(newValue) }
        .sheet(isPresented: $showSearchSheet) {
            NavigationStack {
                bookSearchSheet
            }
        }
    }

    private var backgroundGradient: some View {
        let tokens = themeManager.currentTokens(for: colorScheme)
        return LinearGradient(
            colors: [tokens.background, tokens.primary.opacity(0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var carouselSection: some View {
        ZStack(alignment: .top) {
            ForEach(Array(carouselBooks.enumerated()), id: \.element.id) { index, book in
                if let geometry = geometry(for: index) {
                    BookCarouselCard(
                        book: book,
                        isActive: index == selectedIndex,
                        geometry: geometry
                    )
                    .frame(width: 320, height: 320)
                    .scaleEffect(geometry.scale)
                    .rotationEffect(.degrees(geometry.rotation))
                    .offset(animateIn ? geometry.finalOffset : geometry.initialOffset)
                    .opacity(geometry.opacity)
                    .zIndex(geometry.zIndex)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                            selectedIndex = index
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        .animation(.interpolatingSpring(stiffness: 120, damping: 18).speed(0.95), value: selectedIndex)
        .animation(.easeOut(duration: 0.5), value: animateIn)
        .onChange(of: carouselBooks.map { $0.id }) { _, _ in
            resetEntryAnimation()
        }
    }

    private var dotsSection: some View {
        HStack(spacing: 10) {
            ForEach(visibleDotIndices, id: \.self) { index in
                DotView(
                    color: dotColor(for: index),
                    size: index == selectedIndex ? 12 : 8
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: selectedIndex)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: visibleDotIndices)
    }

    private var bookDetailSection: some View {
        VStack(spacing: 32) {
            if let book = activeBook {
                VStack(spacing: 0) {
                    Text(book.title)
                        .font(DS.Typography.title2)
                        .tracking(DS.Typography.tightTracking(for: 20))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundColor(
                            themeManager.activeRoles.color(role: .primary, tone: 30)
                            ?? DS.Colors.primaryText
                        )

                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(DS.Typography.fraunces(size: 14, weight: .regular))
                            .tracking(DS.Typography.tightTracking(for: 14))
                            .padding(.top, 4)
                            .lineLimit(1)
                            .foregroundColor(
                                themeManager.activeRoles.color(role: .primary, tone: 40)
                                ?? DS.Colors.primaryText
                            )
                    }
                }
                .padding(.horizontal, 64)
                .frame(height: titleAuthorBlockHeight, alignment: .bottom)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 24) {
                        if let description = book.bookDescription, !description.isEmpty {
                            Text(description)
                                .font(DS.Typography.fraunces(size: 11, weight: .regular))
                                .tracking(DS.Typography.tightTracking(for: 11))
                                .foregroundColor(
                                    themeManager.activeRoles.color(role: .primary, tone: 40)
                                    ?? DS.Colors.primaryText
                                )
                                .lineLimit(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }

                        BookStatsView(book: book)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .lineLimit(10)
                    }
                    .frame(height: detailsFixedHeight, alignment: .top)
                    .padding(.horizontal, 64)
                }
            } else {
                Text("Add a book to get started")
                    .font(DS.Typography.body)
                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.6))
            }
        }
    }

    private var bottomToolbar: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(spacing: 0) {
                Spacer().frame(height: 12)

                HStack {
                    Spacer()
                    selectButtonControl
                        .shadow(color: themeManager.currentTokens(for: colorScheme).primary.opacity(0.22), radius: 22, x: 0, y: 12)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    addBookButton
                        .padding(.trailing, 32)
                        .offset(x: 0)
                }

                if let error = selectionError {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.destructive)
                        .multilineTextAlignment(.leading)
                        .padding(.top, DS.Spacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100, alignment: .top)
    }

    private var selectButtonControl: some View {
        Button(action: confirmSelection) {
            Text(isProcessingSelection ? (selectionStatus ?? "Choosing…") : "Select this book")
                .font(DS.Typography.bodyBold)
        }
        .buttonStyle(PaletteAwarePrimaryButtonStyle())
        .disabled(activeBook == nil || isProcessingSelection)
    }

    private var addBookButton: some View {
        Button(action: { if !isProcessingSelection { showSearchSheet = true } }) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .regular))
        }
        .buttonStyle(PaletteAwarePrimaryButtonStyle(iconDiameter: addButtonDiameter))
        .disabled(isProcessingSelection)
    }

    private func confirmSelection() {
        guard let book = activeBook else { return }
        selectionError = nil

        Task { @MainActor in
            isProcessingSelection = true
            selectionStatus = "Opening book…"

            book.lastAccessed = Date()
            try? modelContext.save()

            navigationState.navigateToBook(title: book.title)
            selectionStatus = nil
            isProcessingSelection = false
        }
    }

    private func handleInitialAppear() {
        adjustSelectionForBookChanges()
        resetEntryAnimation()

        if let book = activeBook {
            Task { await themeManager.activateTheme(for: book) }
        }
    }

    private func adjustSelectionForBookChanges() {
        if selectedIndex >= carouselBooks.count {
            selectedIndex = max(0, carouselBooks.count - 1)
        }
    }

    private func handleSelectionChange(_ newValue: Int) {
        guard newValue < carouselBooks.count else { return }
        let book = carouselBooks[newValue]
        Task { await themeManager.activateTheme(for: book) }
        // Do not reset entry animation on selection; keeps layout stable
    }

    private func resetEntryAnimation() {
        withAnimation(.easeOut(duration: 0.001)) { animateIn = false }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.5)) { animateIn = true }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                if horizontal < -40 {
                    let next = min(selectedIndex + 1, carouselBooks.count - 1)
                    if next != selectedIndex {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            selectedIndex = next
                        }
                    }
                } else if horizontal > 40 {
                    let prev = max(selectedIndex - 1, 0)
                    if prev != selectedIndex {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            selectedIndex = prev
                        }
                    }
                }
            }
    }

    private var visibleDotIndices: [Int] {
        guard !carouselBooks.isEmpty else { return [] }
        let lower = max(0, selectedIndex - 3)
        let upper = min(carouselBooks.count - 1, selectedIndex + 3)
        return Array(lower...upper)
    }

    private func dotColor(for index: Int) -> Color {
        let base = themeManager.seedColor(at: 0) ?? themeManager.currentTokens(for: colorScheme).primary
        let distance = abs(index - selectedIndex)
        switch distance {
        case 0: return base
        case 1: return base.opacity(0.6)
        case 2: return base.opacity(0.4)
        default: return base.opacity(0.2)
        }
    }

    private func geometry(for index: Int) -> CarouselGeometry? {
        guard !carouselBooks.isEmpty else { return nil }
        let relativePosition = index - selectedIndex
        guard abs(relativePosition) <= 2 else { return nil }

        // Fan-style layout constants (tweak as needed)
        let rotations: [Int: Double] = [-2: -14, -1: -7, 0: 0, 1: 7, 2: 14]
        let scales: [Int: CGFloat] = [-2: 0.78, -1: 0.88, 0: 1.0, 1: 0.88, 2: 0.78]
        let opacities: [Int: Double] = [-2: 1.0, -1: 1.0, 0: 1.0, 1: 1.0, 2: 1.0]
        let offsetsX: [Int: CGFloat] = [-2: -520, -1: -260, 0: 0, 1: 260, 2: 520]
        let offsetsY: [Int: CGFloat] = [-2: 48, -1: 32, 0: 0, 1: 32, 2: 48]

        let rotation = rotations[relativePosition] ?? 0
        let scale = scales[relativePosition] ?? 1
        let opacity = opacities[relativePosition] ?? 1
        let finalOffset = CGSize(width: offsetsX[relativePosition] ?? 0, height: offsetsY[relativePosition] ?? 0)
        let zIndex = Double(10 - abs(relativePosition))

        // Entry animation: slide softly from above/side
        var initialOffset = finalOffset
        if relativePosition == 0 {
            initialOffset.height -= 100
        } else {
            initialOffset.width *= 1.15
            initialOffset.height -= 40
        }

        return CarouselGeometry(
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            finalOffset: finalOffset,
            initialOffset: initialOffset,
            zIndex: zIndex
        )
    }

    private var bookSearchSheet: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Add a book")
                .font(DS.Typography.headline)
                .padding(.top, DS.Spacing.md)

            BookSearchView(
                title: "Find your book",
                description: "Search Google Books and pick the cover that matches.",
                placeholder: "Title, author, or ISBN",
                minimumCharacters: 3,
                selectionHint: "Tap to add",
                clearOnSelect: true,
                onSelect: handleBookSelection
            )

            if isProcessingSelection {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text(selectionStatus ?? "Adding book…")
                        .font(DS.Typography.caption)
                }
                .padding(.vertical, DS.Spacing.xs)
            }

            if let selectionError {
                Text(selectionError)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.destructive)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showSearchSheet = false }
            }
        }
    }

    private func handleBookSelection(_ metadata: BookMetadata) {
        selectionError = nil
        selectionStatus = nil

        Task { @MainActor in
            isProcessingSelection = true
            selectionStatus = "Adding \(metadata.title)…"

            do {
                let primaryAuthor = metadata.authors.first
                let book = try bookService.findOrCreateBook(
                    title: metadata.title,
                    author: primaryAuthor,
                    triggerMetadataFetch: false
                )

                book.lastAccessed = Date()
                bookService.applyMetadata(metadata, to: book)

                Task { await themeManager.activateTheme(for: book) }

                // Kick off idea extraction in background just like onboarding
                let extractionViewModel = IdeaExtractionViewModel(
                    openAIService: openAIService,
                    bookService: bookService
                )
                Task.detached(priority: .background) {
                    await extractionViewModel.loadOrExtractIdeas(from: metadata.title, metadata: metadata)
                }

                selectionStatus = nil
                isProcessingSelection = false
                showSearchSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let index = carouselBooks.firstIndex(where: { $0.id == book.id }) {
                        selectedIndex = index
                    } else {
                        selectedIndex = 0
                    }
                }
            } catch {
                selectionStatus = nil
                selectionError = error.localizedDescription
                isProcessingSelection = false
            }
        }
    }
}

// MARK: - Supporting Types
private struct CarouselGeometry {
    let rotation: Double
    let scale: CGFloat
    let opacity: Double
    let finalOffset: CGSize
    let initialOffset: CGSize
    let zIndex: Double
}

private struct BookCarouselCard: View {
    let book: Book
    let isActive: Bool
    let geometry: CarouselGeometry
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(0.5))
                .frame(width: 468, height: 468)
                .blur(radius: 120)

            BookCoverView(
                thumbnailUrl: book.thumbnailUrl,
                coverUrl: book.coverImageUrl,
                isLargeView: true,
                cornerRadius: 16
            )
            .frame(maxWidth: 240, maxHeight: 320)
            .shadow(color: Color.black.opacity(isActive ? 0.28 : 0.12), radius: isActive ? 24 : 12, x: 0, y: 18)
        }
    }

    private var glowColor: Color {
        themeManager.activeRoles.color(role: .primary, tone: 90)
            ?? themeManager.currentTokens(for: colorScheme).primaryContainer
    }
}

private struct DotView: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

private struct BookStatsView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryText
                .font(DS.Typography.fraunces(size: 11, weight: .regular))
                .tracking(DS.Typography.tightTracking(for: 11))
                .foregroundColor(
                    themeColorT40
                )
            statsText
                .font(DS.Typography.fraunces(size: 11, weight: .regular))
                .tracking(DS.Typography.tightTracking(for: 11))
                .foregroundColor(
                    themeColorT40
                )
        }
    }

    private var themeColorT40: Color {
        themeManager.activeRoles.color(role: .primary, tone: 40)
        ?? DS.Colors.primaryText
    }

    private var summaryText: Text {
        let totalIdeas = book.ideas?.count ?? 0
        let mastered = book.ideas?.filter { $0.masteryLevel >= 3 }.count ?? 0
        if totalIdeas == 0 {
            return Text("We haven’t extracted ideas from this book yet.")
        } else {
            return Text("\(book.title) has ")
                + Text("\(totalIdeas)").italic()
                + Text(" unique ideas. You’ve mastered ")
                + Text("\(mastered)").italic()
                + Text(".")
        }
    }

    private var statsText: Text {
        let bookIdentifier = book.id.uuidString
        let descriptor = FetchDescriptor<IdeaCoverage>(
            predicate: #Predicate { $0.bookId == bookIdentifier }
        )
        let coverages = (try? modelContext.fetch(descriptor)) ?? []
        let totalQuestions = coverages.reduce(0) { $0 + $1.totalQuestionsSeen }
        let totalCorrect = coverages.reduce(0) { $0 + $1.totalQuestionsCorrect }
        let accuracyPercent = totalQuestions > 0 ? (Double(totalCorrect) / Double(totalQuestions)) * 100.0 : 0.0
        let ideaCount = book.ideas?.count ?? 0
        let coveragePercent: Double
        if ideaCount > 0 {
            coveragePercent = CoverageService(modelContext: modelContext)
                .calculateBookCoverage(bookId: bookIdentifier, totalIdeas: ideaCount)
        } else {
            coveragePercent = 0.0
        }

        return Text("Coverage sits at ")
            + Text("\(Int(coveragePercent))% ").italic()
            + Text("• Accuracy ")
            + Text("\(Int(accuracyPercent))%.").italic()
    }
}
