import SwiftUI

/// Full-screen loader shown during idea extraction.
/// Visual parts:
/// 1) Book cover (same size as carousel: 240x320, 16pt radius)
/// 2) Pulsing halo behind the cover (60 BPM: ~1s cycle, scale + opacity pulse)
/// 3) Four corner handles in the seed color
/// 4) Horizontal scanner line sweeping top -> bottom in Primary T30
/// 5) Loading copy cycling every 2s
struct IdeaExtractionLoaderView: View {
    @Binding var isPresented: Bool
    let thumbnailUrl: String?
    let coverUrl: String?

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    // Animations
    @State private var haloMaxState = true
    @State private var handleBreath = false
    @State private var scannerPhase: CGFloat = 0.0 // 0..1 top->bottom; ping-pong with autoreverse
    @State private var wordIndex: Int = 0
    @State private var dotCount: Int = 1
    @State private var ellipsisWidth: CGFloat = 0
    @State private var maxWordWidth: CGFloat = 0
    @State private var animationStartDate: Date = Date()

    private let coverSize = CGSize(width: 240, height: 320)
    private let coverCornerRadius: CGFloat = 16

    // Loading copy – cycles every 2 seconds
    private let words: [String] = [
        "extracting","decoding","parsing","isolating","distilling","deriving","abstracting","summarizing","identifying","highlighting","indexing","tagging","linking","clustering","ranking","mining","dredging","panning","sifting","screening","separating","refining","filtering","winnowing","sieving","skimming","triaging","pruning","deduplicating","disambiguating","tokenizing","chunking","segmenting","annotating","cross-referencing","normalizing","mapping","modeling","denoising","surfacing","querying","scanning","scraping","harvesting","gleaning","eluting","clarifying","concentrating","triangulating","corroborating","reconciling","nuggetising","argument-mining","idea-decanting","truth-trawling","tomfoolering"
    ]

    var body: some View {
        ZStack {
            background

            VStack(spacing: 32) {
                ZStack {
                    // Pulsing halo behind the cover (Primary T95 @ 100% opacity)
                    pulseHalo

                    // Corner handles frame
                    cornerHandles
                        .frame(width: coverSize.width + 80, height: coverSize.height + 80)
                        .allowsHitTesting(false)

                    // Book cover
                    BookCoverView(
                        thumbnailUrl: thumbnailUrl,
                        coverUrl: coverUrl,
                        isLargeView: true,
                        cornerRadius: coverCornerRadius
                    )
                    .frame(width: coverSize.width, height: coverSize.height)
                    .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 14)
                    .overlay(alignment: .topLeading) { scannerOverlay }
                }
                // Fix the container size so pulsing halo does not shift layout
                .frame(width: 468, height: 468, alignment: .center)

                loadingCopy
            }
            .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            // no-op; animations stop naturally with view removal
        }
        // Block all underlying touches
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }

    // MARK: - Background
    private var background: some View {
        // Match AddBookOverlay background treatment exactly
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.18))
    }

    // MARK: - Colors
    private var seedColor: Color {
        themeManager.seedColor(at: 0)
        ?? themeManager.activeRoles.color(role: .primary, tone: 40)
        ?? DS.Colors.primaryText
    }

    private var primaryT30: Color {
        themeManager.activeRoles.color(role: .primary, tone: 30)
        ?? DS.Colors.primaryText.opacity(0.9)
    }

    private var primaryT95: Color {
        themeManager.activeRoles.color(role: .primary, tone: 95)
        ?? seedColor
    }

    // MARK: - Halo
    private var pulseHalo: some View {
        // Diameter: 468 (max) -> 240 (min); Blur: 120 (max) -> 80 (min)
        let diameter = haloMaxState ? 468.0 : 240.0
        let blur = haloMaxState ? 120.0 : 80.0
        return Circle()
            .fill(primaryT95) // 100% opacity per spec
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .compositingGroup()
            .blendMode(.plusLighter) // make the halo visibly luminous over material
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: haloMaxState)
            .allowsHitTesting(false)
    }

    // MARK: - Corner Handles
    private var cornerHandles: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let len: CGFloat = 26
            let thickness: CGFloat = 3
            let inset: CGFloat = 8
            let scale = handleBreath ? 1.03 : 0.97
            ZStack {
                // TL
                handlePath(len: len, thickness: thickness)
                    .foregroundStyle(seedColor)
                    .position(x: inset + len/2, y: inset + len/2)
                    .scaleEffect(scale, anchor: .topLeading)
                // TR
                handlePath(len: len, thickness: thickness)
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(seedColor)
                    .position(x: w - inset - len/2, y: inset + len/2)
                    .scaleEffect(scale, anchor: .topTrailing)
                // BR
                handlePath(len: len, thickness: thickness)
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(seedColor)
                    .position(x: w - inset - len/2, y: h - inset - len/2)
                    .scaleEffect(scale, anchor: .bottomTrailing)
                // BL
                handlePath(len: len, thickness: thickness)
                    .rotationEffect(.degrees(270))
                    .foregroundStyle(seedColor)
                    .position(x: inset + len/2, y: h - inset - len/2)
                    .scaleEffect(scale, anchor: .bottomLeading)
            }
            .animation(
                .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                value: handleBreath
            )
        }
    }

    private func handlePath(len: CGFloat, thickness: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().frame(width: len, height: thickness)
            Rectangle().frame(width: thickness, height: len)
        }
        .cornerRadius(thickness/2, antialiased: true)
        .shadow(color: seedColor.opacity(0.20), radius: 2, x: 0, y: 1)
    }

    // MARK: - Scanner
    private var scannerOverlay: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let W = geo.size.width
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(animationStartDate)
                let period: Double = 2.4 // full up+down
                let u = (t / period).truncatingRemainder(dividingBy: 1.0)
                // Start at center: phase shift by +0.25
                let uShift = (u + 0.25).truncatingRemainder(dividingBy: 1.0)
                // Smooth ping-pong 0->1->0 using cosine
                let progress = 0.5 - 0.5 * cos(2.0 * .pi * uShift)
                let y = progress * H

                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(primaryT30)
                        .frame(height: 2)
                        .offset(y: y)
                        .compositingGroup()
                }
                .frame(width: W, height: H, alignment: .top)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Loading Copy
    private var loadingCopy: some View {
        let tokens = themeManager.currentTokens(for: colorScheme)
        let word = words[wordIndex % words.count]
        let font = DS.Typography.fraunces(size: 20, weight: .regular)

        return ZStack(alignment: .center) {
            // Hidden measurements: max width across all words and width of "..."
            measurementView(font: font)
                .frame(width: 0, height: 0)
                .hidden()

            // Visible content with fixed, pre-measured width so it never re-centers
            HStack(spacing: 0) {
                Text(word)
                    .font(font)
                    .foregroundColor(tokens.onSurface)
                    .fixedSize() // keep glyph metrics stable
                ZStack(alignment: .leading) {
                    Text(String(repeating: ".", count: dotCount))
                        .font(font)
                        .foregroundColor(tokens.onSurface)
                        .fixedSize()
                }
                .frame(width: max(ellipsisWidth, 1), alignment: .leading)
            }
            .frame(width: maxWordWidth + ellipsisWidth, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // Hidden helper that measures widths for layout stabilization
    private func measurementView(font: Font) -> some View {
        VStack(spacing: 0) {
            // Measure ellipsis width
            Text("...")
                .font(font)
                .background(
                    GeometryReader { g in
                        Color.clear
                            .preference(key: EllipsisWidthKey.self, value: g.size.width)
                    }
                )
                .opacity(0)
            // Measure every word to get the maximum width
            ForEach(words.indices, id: \.self) { i in
                Text(words[i])
                    .font(font)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(key: WordMaxWidthKey.self, value: g.size.width)
                        }
                    )
                    .opacity(0)
            }
        }
        .onPreferenceChange(EllipsisWidthKey.self) { w in ellipsisWidth = max(ellipsisWidth, w) }
        .onPreferenceChange(WordMaxWidthKey.self) { w in maxWordWidth = max(maxWordWidth, w) }
    }

    // MARK: - Animation drivers
    private func startAnimations() {
        // Halo pulse (max -> min -> max ...)
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            haloMaxState.toggle()
        }

        // Handle breathing
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            handleBreath.toggle()
        }

        animateScanner()
        cycleWords()
        startDots()
    }

    private func animateScanner() {
        // Continuous ping-pong with easing (top<->bottom) using chained animations
        // Start time-based animation timeline
        animationStartDate = Date()
    }

    private func cycleWords() {
        // 2s cadence for word changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard isPresented else { return }
            wordIndex = (wordIndex + 1) % words.count
            cycleWords()
        }
    }

    private func startDots() {
        let interval: TimeInterval = 0.33
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard isPresented else { return }
            dotCount = (dotCount % 3) + 1
            startDots()
        }
    }
}

// PreferenceKey to measure the width of "..." in the current font
private struct EllipsisWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WordMaxWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
