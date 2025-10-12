import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var showSearchSheet = false // legacy sheet; replaced by overlay
    @State private var isAddOverlayActive = false
    @Namespace private var addOverlayNamespace
    @GestureState private var dragX: CGFloat = 0
    @State private var themeUpdateTask: Task<Void, Never>? = nil
    @State private var extractionTask: Task<Void, Never>? = nil
    @State private var isTransitioning: Bool = false
    // Details text transition state
    @State private var detailDisplayedIndex: Int = 0
    @State private var detailBaseOpacity: Double = 1.0
    @State private var detailDragOpacityFreeze: Double? = nil
    @State private var detailsTransitionInFlight: Bool = false
    // Tap bounce animation state
    @State private var tappedCardIndex: Int? = nil
    @State private var tapScale: CGFloat = 1.0

    private let addButtonDiameter: CGFloat = 52
    private let addButtonGap: CGFloat = 12
    // Prevent layout jumping: fix heights for title, author, and details block
    private let titleAuthorBlockHeight: CGFloat = 72 // fits 2-line title + 1-line author + 4pt gap
    private let detailsFixedHeight: CGFloat = 140 // description + stats area
    // Dots positioning and carousel offset to avoid overlap
    private let dotsTop: CGFloat = 40
    private let dotRowHeight: CGFloat = 10
    private let dotSpacing: CGFloat = 14
    private let dotCarouselGap: CGFloat = 0
    private var carouselTopOffset: CGFloat { dotsTop + dotRowHeight + dotCarouselGap }

    private var bookService: BookService {
        BookService(modelContext: modelContext)
    }

    // Unified spring for all selection changes
    private var selectionSpring: Animation {
        .spring(response: 0.5, dampingFraction: 0.70, blendDuration: 0.05)
    }

    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }

    private var carouselBooks: [Book] {
        // Unlimited carousel; rendering already windows visible neighbors
        allBooks
    }

    private var activeBook: Book? {
        guard !carouselBooks.isEmpty, selectedIndex < carouselBooks.count else { return nil }
        return carouselBooks[selectedIndex]
    }

    private var activeDetailBook: Book? {
        guard !carouselBooks.isEmpty else { return nil }
        let safeIndex = max(0, min(detailDisplayedIndex, carouselBooks.count - 1))
        guard safeIndex < carouselBooks.count else { return nil }
        return carouselBooks[safeIndex]
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
        .safeAreaInset(edge: .bottom) {
            ZStack {
                // Centered primary CTA
                selectButtonControl
                    .padding(.horizontal, 24)

                // Floating add button on the right
                HStack { Spacer(); addBookButton }
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 8)
            .background(Color.clear)
        }
        // Present Cmd+K overlay inline so it always shows
        .overlay {
            if isAddOverlayActive {
                AddBookOverlay(
                    isPresented: $isAddOverlayActive,
                    maxResults: 7,
                    onSelect: handleBookSelection,
                    matchedId: "addControl",
                    namespace: addOverlayNamespace
                )
                .environmentObject(themeManager)
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .overlay(alignment: .top) {
            dotsSection
                .padding(.top, dotsTop)
                .allowsHitTesting(false)
                .opacity(isAddOverlayActive ? 0 : 1)
        }
        .onAppear { handleInitialAppear() }
        .onChange(of: carouselBooks.count) { _, _ in adjustSelectionForBookChanges() }
        .onChange(of: selectedIndex) { _, newValue in handleSelectionChange(newValue) }
        .onDisappear {
            themeUpdateTask?.cancel()
            extractionTask?.cancel()
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
                if let geometry = geometry(for: index, dragProgress: currentDragProgress) {
                    BookCarouselCard(
                        book: book,
                        isActive: index == selectedIndex,
                        geometry: geometry
                    )
                    .frame(width: 320, height: 320)
                    .scaleEffect(geometry.scale * (tappedCardIndex == index ? tapScale : 1.0))
                    .rotationEffect(.degrees(geometry.rotation))
                    .offset(animateIn ? geometry.finalOffset : geometry.initialOffset)
                    .opacity(geometry.opacity)
                    .zIndex(geometry.zIndex)
                    .onTapGesture {
                        guard abs(currentDragProgress) < 0.02, !isTransitioning, !isProcessingSelection else { return }
                        // Subtle bounce on tap for organic feel
                        tappedCardIndex = index
                        withAnimation(.spring(response: 0.12, dampingFraction: 0.68)) { tapScale = 0.92 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) { tapScale = 1.0 }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                            if tappedCardIndex == index { tappedCardIndex = nil }
                        }

                        // If tapping the active card, confirm immediately. Otherwise, focus it then confirm.
                        if index == selectedIndex {
                            // Let the bounce be visible before navigating
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                                confirmSelection()
                            }
                        } else {
                            // Stagger: finish bounce-in before shifting focus
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                                isTransitioning = true
                                withAnimation(selectionSpring) { selectedIndex = index }
                                // Allow the focus animation to complete before navigating
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                    isTransitioning = false
                                    confirmSelection()
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(interactiveDragGesture)
        .animation(.easeOut(duration: 0.5), value: animateIn)
        .onChange(of: carouselBooks.map { $0.id }) { _, _ in
            resetEntryAnimation()
        }
    }

    private var dotsSection: some View {
        ZStack {
            ForEach(visibleDotIndices, id: \.self) { index in
                let relative = Double(index - selectedIndex) + currentDragProgress
                let absRel = abs(relative)
                let incomingIndex: Int? = {
                    let dir = currentDragProgress
                    guard abs(dir) > 0.5 else { return nil }
                    return selectedIndex + (dir < 0 ? 1 : -1)
                }()
                let baseSize = dotSize(forRelative: absRel)
                let size = baseSize * ((incomingIndex == index) ? 1.06 : 1.0)
                DotView(
                    color: dotColor(for: index),
                    size: size
                )
                .opacity(dotOpacity(forRelative: absRel))
                .offset(x: offsetForDot(index))
            }
        }
        .frame(maxWidth: .infinity, minHeight: dotRowHeight, maxHeight: dotRowHeight, alignment: .center)
    }

    private var bookDetailSection: some View {
        VStack(spacing: 32) {
            if let book = activeDetailBook {
                Group {
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
                }
                .id(book.id)
                .opacity(detailEffectiveOpacity)
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
        .dsPalettePrimaryButton()
        .disabled(activeBook == nil || isProcessingSelection)
    }

    private var addBookButton: some View {
        Button(action: {
            guard !isProcessingSelection else { return }
            triggerAddButtonHaptic()
            withAnimation(.spring(response: 0.40, dampingFraction: 0.88)) {
                isAddOverlayActive = true
            }
        }) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .regular))
        }
        .matchedGeometryEffect(id: "addControl", in: addOverlayNamespace)
        .dsPaletteIconButton(diameter: addButtonDiameter)
        .accessibilityIdentifier("BookSelectionAddButton")
        .disabled(isProcessingSelection)
    }

    private func confirmSelection() {
        guard let book = activeBook else { return }
        selectionError = nil

        Task { @MainActor in
            triggerConfirmHaptic()
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

        // Initialize details to match the selected item
        detailDisplayedIndex = selectedIndex
        detailBaseOpacity = 1.0
        detailDragOpacityFreeze = nil

        if let book = activeBook {
            Task { await themeManager.activateTheme(for: book) }
        }
    }

    private func adjustSelectionForBookChanges() {
        if selectedIndex >= carouselBooks.count {
            selectedIndex = max(0, carouselBooks.count - 1)
        }
        if detailDisplayedIndex >= carouselBooks.count {
            detailDisplayedIndex = max(0, carouselBooks.count - 1)
        }
    }

    private func handleSelectionChange(_ newValue: Int) {
        guard newValue < carouselBooks.count else { return }
        let book = carouselBooks[newValue]
        triggerSelectionHaptic()
        // Defer theme change until selection animation settles to avoid jank
        themeUpdateTask?.cancel()
        let delayNs: UInt64 = 220_000_000 // ~0.22s
        themeUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            await themeManager.activateTheme(for: book)
        }
        // Do not reset entry animation on selection; keeps layout stable
        prefetchAdjacentCovers(around: newValue)

        // If selection changed without a drag commit (e.g., tap), run details crossfade
        if !detailsTransitionInFlight {
            detailsTransitionInFlight = true
            // No drag component; keep it fully visible until we animate out
            detailDragOpacityFreeze = 1.0
            withAnimation(.easeIn(duration: 0.18)) {
                detailBaseOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                detailDisplayedIndex = newValue
                detailDragOpacityFreeze = nil
                withAnimation(.easeIn(duration: 0.20)) {
                    detailBaseOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    detailsTransitionInFlight = false
                }
            }
        }
    }

    // MARK: - Haptics
    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    private func triggerConfirmHaptic() {
        #if canImport(UIKit)
        if #available(iOS 13.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred(intensity: 0.7)
        } else {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        #endif
    }

    private func triggerAddButtonHaptic() {
        #if canImport(UIKit)
        // Subtle tap to reinforce opening the overlay
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.75)
        #endif
    }

    private func resetEntryAnimation() {
        withAnimation(.easeOut(duration: 0.001)) { animateIn = false }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.5)) { animateIn = true }
        }
        // Prefetch initial neighbors for smoother first interactions
        prefetchAdjacentCovers(around: selectedIndex)
    }

    private func prefetchAdjacentCovers(around index: Int) {
        guard !carouselBooks.isEmpty else { return }
        let indices = [index - 1, index + 1].filter { $0 >= 0 && $0 < carouselBooks.count }
        let targetSize = CGSize(width: 240, height: 320)
        for i in indices {
            let b = carouselBooks[i]
            let urlString = b.coverImageUrl ?? b.thumbnailUrl
            if let urlString { ImageCache.shared.prefetch(urlString: urlString, targetSize: targetSize) }
        }
    }

    private var interactiveDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($dragX) { value, state, _ in
                state = value.translation.width
            }
            .onChanged { _ in
                // While dragging, unfreeze so opacity follows gesture
                detailDragOpacityFreeze = nil
            }
            .onEnded { value in
                guard !carouselBooks.isEmpty else { return }
                let baseSpacing: CGFloat = 240
                let p = Double(value.translation.width / baseSpacing)
                let pp = Double(value.predictedEndTranslation.width / baseSpacing)
                let commitThreshold = 0.35

                let startIndex = selectedIndex
                var target = startIndex
                if (p <= -commitThreshold || pp <= -commitThreshold) {
                    target = min(startIndex + 1, carouselBooks.count - 1)
                } else if (p >= commitThreshold || pp >= commitThreshold) {
                    target = max(startIndex - 1, 0)
                }

                if target != startIndex {
                    // Freeze current drag-driven opacity and finish fading out
                    detailsTransitionInFlight = true
                    let pClamped = max(0.0, min(1.0, abs(p)))
                    let frozenDrag = 1.0 - pow(pClamped, 1.6)
                    detailDragOpacityFreeze = frozenDrag
                    withAnimation(.easeIn(duration: 0.18)) {
                        detailBaseOpacity = 0.0
                    }
                    // After outgoing fade completes, swap details and fade in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        detailDisplayedIndex = target
                        detailDragOpacityFreeze = nil
                        withAnimation(.easeIn(duration: 0.10)) {
                            detailBaseOpacity = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            detailsTransitionInFlight = false
                        }
                    }
                    isTransitioning = true
                    withAnimation(selectionSpring) { selectedIndex = target }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { isTransitioning = false }
                } else {
                    // Cancel: return opacity smoothly and clear freeze
                    let pClamped = max(0.0, min(1.0, abs(p)))
                    let frozenDrag = 1.0 - pow(pClamped, 1.6)
                    detailDragOpacityFreeze = frozenDrag
                    withAnimation(.easeOut(duration: 0.18)) {
                        detailBaseOpacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        detailDragOpacityFreeze = nil
                    }
                    withAnimation(selectionSpring) { }
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
        case 1: return base.opacity(0.75)
        case 2: return base.opacity(0.55)
        default: return base.opacity(0.35)
        }
    }

    private func dotSize(forRelative d: Double) -> CGFloat {
        // Reduced sizes at integer distances: 0 -> 10, 1 -> 8, 2 -> 6, 3+ -> 4
        let keys = [0.0, 1.0, 2.0, 3.0]
        let vals: [Double: Double] = [0:10, 1:8, 2:6, 3:4]
        return CGFloat(lerpTable(d: d, keys: keys, vals: vals))
    }

    private func dotOpacity(forRelative d: Double) -> Double {
        // Opacities at integer distances: 0 -> 1.0, 1 -> 0.9, 2 -> 0.7, 3+ -> 0.5
        let keys = [0.0, 1.0, 2.0, 3.0]
        let vals: [Double: Double] = [0:1.0, 1:0.9, 2:0.7, 3:0.5]
        return lerpTable(d: d, keys: keys, vals: vals)
    }

    private func lerpTable(d: Double, keys: [Double], vals: [Double: Double]) -> Double {
        let sorted = keys.sorted()
        let clamped = max(sorted.first ?? 0.0, min(sorted.last ?? 0.0, d))
        var lowerKey = sorted.first ?? 0.0
        var upperKey = sorted.last ?? 0.0
        for i in 0..<(sorted.count - 1) {
            if clamped >= sorted[i] && clamped <= sorted[i+1] {
                lowerKey = sorted[i]
                upperKey = sorted[i+1]
                break
            }
        }
        if lowerKey == upperKey { return vals[lowerKey] ?? 0 }
        let a = vals[lowerKey] ?? 0
        let b = vals[upperKey] ?? a
        let t = (clamped - lowerKey) / (upperKey - lowerKey)
        return a + (b - a) * t
    }

    // Variable-gap spacing for dots: closer near the center, tighter further out
    private func gapForStep(distance: Int) -> CGFloat {
        switch distance {
        case 1: return 16
        case 2: return 14
        default: return 12
        }
    }

    private func offsetForDot(_ index: Int) -> CGFloat {
        guard !carouselBooks.isEmpty else { return 0 }
        let rel = Double(index - selectedIndex) - currentDragProgress
        if rel == 0 { return 0 }
        let sign: CGFloat = rel > 0 ? 1 : -1
        let absRel = abs(rel)
        let whole = Int(floor(absRel))
        let frac = absRel - Double(whole)

        var sum: CGFloat = 0
        if whole > 0 {
            for d in 1...whole { sum += gapForStep(distance: d) }
        }
        let nextGap = gapForStep(distance: whole + 1)
        let total = sum + CGFloat(frac) * nextGap
        return sign * total
    }

    private func geometry(for index: Int, dragProgress: Double) -> CarouselGeometry? {
        guard !carouselBooks.isEmpty else { return nil }

        // progress is negative when dragging left toward next item
        let rp = Double(index - selectedIndex) + dragProgress
        // Limit visible neighbors: show ±1 while interacting, ±2 when idle
        let span = visibleSpan
        guard abs(rp) <= span else { return nil }

        // Fan-style layout reference points (tighter for snappier feel)
        let rotations: [Int: Double] = [-2: -12, -1: -6, 0: 0, 1: 6, 2: 12]
        let scales: [Int: Double] = [-2: 0.82, -1: 0.90, 0: 1.0, 1: 0.90, 2: 0.82]
        let opacities: [Int: Double] = [-2: 1.0, -1: 1.0, 0: 1.0, 1: 1.0, 2: 1.0]
        let offsetsX: [Int: Double] = [-2: -520, -1: -260, 0: 0, 1: 260, 2: 520]
        let offsetsY: [Int: Double] = [-2: 44, -1: 28, 0: 0, 1: 28, 2: 44]

        let rotation = value(for: rp, in: rotations, eased: true)
        let scale = value(for: rp, in: scales, eased: true)
        let opacity = value(for: rp, in: opacities, eased: true)
        let offsetX = value(for: rp, in: offsetsX, eased: true)
        let offsetY = value(for: rp, in: offsetsY, eased: true)

        let finalOffset = CGSize(width: offsetX, height: offsetY)
        let zIndex = Double(10 - abs(rp))

        // Entry animation: slide softly from above/side based on nearest slot
        var initialOffset = finalOffset
        if abs(rp) < 0.5 {
            initialOffset.height -= 100
        } else {
            initialOffset.width *= 1.15
            initialOffset.height -= 40
        }

        return CarouselGeometry(
            rotation: rotation,
            scale: CGFloat(scale),
            opacity: opacity,
            finalOffset: finalOffset,
            initialOffset: initialOffset,
            zIndex: zIndex
        )
    }

    // Normalized interactive progress in [-1, 1], respecting edges
    private var currentDragProgress: Double {
        guard !carouselBooks.isEmpty else { return 0 }
        let baseSpacing: CGFloat = 240 // matches slot spacing used by offsetsX
        let raw = Double(dragX / baseSpacing)
        let atFirst = selectedIndex == 0
        let atLast = selectedIndex == (carouselBooks.count - 1)

        // Apply rubber-banding only when dragging toward a non-existent neighbor
        let k = 0.6
        func band(_ x: Double) -> Double { (x * k) / (abs(x) * k + 1.0) }

        var effective = raw
        if atFirst && raw > 0 { effective = band(raw) }
        if atLast && raw < 0 { effective = -band(-raw) }

        // Always clamp to [-1, 1] for stability
        return max(-1.0, min(1.0, effective))
    }

    // Show fewer neighbors while dragging to cut overdraw
    private var visibleSpan: Double {
        abs(currentDragProgress) > 0.001 ? 1.0 : 2.0
    }

    // MARK: - Details opacity helpers
    private var detailDragOpacity: Double {
        // Ease-in mapping: slow at start, faster near the end
        let p = max(0.0, min(1.0, abs(currentDragProgress)))
        let eased = pow(p, 1.6)
        return 1.0 - eased
    }

    private var detailEffectiveOpacity: Double {
        let dragComponent = detailDragOpacityFreeze ?? detailDragOpacity
        return max(0.0, min(1.0, detailBaseOpacity * dragComponent))
    }

    // Linear interpolation helpers
    private func value(for rp: Double, in table: [Int: Double], eased: Bool = false) -> Double {
        let clamped = max(-2.0, min(2.0, rp))
        let lower = max(-2, min(1, Int(floor(clamped))))
        let upper = lower + 1
        if lower == upper { return table[lower] ?? 0 }
        let a = table[lower] ?? 0
        let b = table[upper] ?? a
        var t = clamped - Double(lower)
        if eased {
            // Smoothstep easing for organic interpolation
            t = t * t * (3 - 2 * t)
        }
        return a + (b - a) * t
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
                maxResults: 12,
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

        // Begin selection flow and extract ideas before navigating to overview.
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

                selectionStatus = "Extracting ideas…"
                showSearchSheet = false
                isAddOverlayActive = false

                let extractionViewModel = IdeaExtractionViewModel(
                    openAIService: openAIService,
                    bookService: bookService
                )

                // Run extraction off the main-actor; navigate when done.
                extractionTask?.cancel()
                extractionTask = Task(priority: .userInitiated) {
                    await extractionViewModel.loadOrExtractIdeas(from: metadata.title, metadata: metadata)
                    await MainActor.run {
                        navigationState.navigateToBook(title: book.title)
                        selectionStatus = nil
                        isProcessingSelection = false
                    }
                }

                // Optionally adjust selection index for visual continuity if user returns.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let index = carouselBooks.firstIndex(where: { $0.id == book.id }) {
                        selectedIndex = index
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
            if isActive {
                // Lightweight gradient glow only for the active card (no blur)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.28), glowColor.opacity(0.0)],
                            center: .center,
                            startRadius: 12,
                            endRadius: 240
                        )
                    )
                    .frame(width: 420, height: 420)
                    .allowsHitTesting(false)
            }

            BookCoverView(
                thumbnailUrl: book.thumbnailUrl,
                coverUrl: book.coverImageUrl,
                isLargeView: true,
                cornerRadius: 16
            )
            .frame(maxWidth: 240, maxHeight: 320)
            // Constant radius shadow; animate opacity only for cheaper compositing
            .shadow(color: Color.black.opacity(isActive ? 0.24 : 0.12), radius: 18, x: 0, y: 14)
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
        if totalIdeas == 0 {
            return Text("We haven’t extracted ideas from this book yet.")
        } else {
            return Text("The ")
                + Text("\(book.title)")
                + Text(" has ")
                + Text("\(totalIdeas)").italic()
                + Text(" unique ideas.")
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

        let coveredIdeas = coverages.filter { $0.isFullyCovered }.count
        let masteredIdeas = book.ideas?.filter { $0.masteryLevel >= 3 }.count ?? 0
        let accuracyRounded = Int(accuracyPercent.rounded())

        return Text("You’ve covered ")
            + Text("\(coveredIdeas)/\(ideaCount)").italic()
            + Text(".\n")
            + Text("You’ve mastered ")
            + Text("\(masteredIdeas)/\(ideaCount)").italic()
            + Text(".\n")
            + Text("Your average accuracy is ")
            + Text("\(accuracyRounded)%").italic()
            + Text(".")
    }
}
