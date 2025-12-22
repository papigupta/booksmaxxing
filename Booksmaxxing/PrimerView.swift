import SwiftUI
import SwiftData

struct PrimerView: View {
    let idea: Idea
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let tightTracking: CGFloat = -0.6
    private let horizontalPadding: CGFloat = 32
    
    @State private var primerService: PrimerService?
    @State private var primer: Primer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var isLoadingMoreExamples = false
    @State private var showAllExamples = false
    
    init(idea: Idea, openAIService: OpenAIService) {
        self.idea = idea
        self.openAIService = openAIService
    }
    
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        NavigationView {
            VStack(spacing: 0) {
                headerView
                contentView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .dsTertiaryButton()
            }
        }
        .background(theme.surface.ignoresSafeArea())
        .onAppear {
            // Initialize primerService with the correct modelContext
            primerService = PrimerService(openAIService: openAIService, modelContext: modelContext)
            loadPrimer()
            UserAnalyticsService.shared.markPrimerOpened()
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Book title with enhanced styling
            Text(idea.bookTitle)
                .font(DS.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(theme.onSurface.opacity(0.7))
                .textCase(.uppercase)
                .tracking(tightTracking)
            
            // Primer title with better hierarchy
            Text(idea.title)
                .font(DS.Typography.title2)
                .fontWeight(.semibold)
                .tracking(tightTracking)
                .foregroundStyle(DS.Colors.primaryText)
                .lineLimit(2)
            
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.lg)
        .background(theme.surface)
    }
    
    @ViewBuilder
    private var contentView: some View {
        ZStack {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let primer = primer {
                primerContentView(primer)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingView: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(spacing: DS.Spacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.primary))
                .scaleEffect(1.2)
            
            Text("Loading primer...")
                .font(DS.Typography.body)
                .foregroundColor(theme.onSurface.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface)
    }
    
    private func errorView(_ error: String) -> some View {
        DSErrorView(
            title: "Error",
            message: error,
            retryAction: { loadPrimer() }
        )
    }
    
    private func primerContentView(_ primer: Primer) -> some View {
        let hasNewContent = hasNewEncodingContent(primer)
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                if hasNewContent {
                    provocationSection(primer)
                    mentalModelSection(primer)
                    deepLogicSection(primer)
                    lensSection(primer)
                    rabbitHoleSection(primer)
                }
                
                if hasNewContent {
                    furtherLearningSection(primer)
                }
                
                if !hasNewContent {
                    legacyContentStack(primer)
                }
                
                refreshButton
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, DS.Spacing.lg)
        }
    }
    
    @ViewBuilder
    private func thesisSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        if !primer.thesis.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Enhanced header for thesis section
                HStack(spacing: DS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(theme.primary)
                            .frame(width: 32, height: 32)
                        
                        DSIcon("lightbulb.fill", size: 16)
                            .foregroundColor(theme.onPrimary)
                    }
                    
                    Text("Core Thesis")
                        .font(DS.Typography.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.onSurface)
                }
                
                // Enhanced thesis content
                Text(primer.thesis)
                    .font(DS.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.onSurface)
                    .lineSpacing(6)
                    .padding(DS.Spacing.lg)
                    .background(theme.surfaceVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.outline, lineWidth: 2)
                    )
                    .cornerRadius(12)
                    .shadow(color: DS.Colors.shadow, radius: 4, x: 0, y: 2)
            }
        }
    }
    
    @ViewBuilder
    private func provocationSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        if !primer.shift.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    DSIcon("bolt.fill", size: 16)
                        .foregroundColor(theme.primary)
                    Text("The Provocation")
                        .font(DS.Typography.headline)
                        .tracking(tightTracking)
                        .foregroundStyle(theme.onSurface)
                }
                
                Text(primer.shift)
                    .font(DS.Typography.bodyEmphasized)
                    .tracking(tightTracking)
                    .foregroundStyle(theme.onSurface)
                    .lineSpacing(4)
                    .padding(DS.Spacing.lg)
                    .background(theme.surfaceVariant)
                    .cornerRadius(10)
            }
        }
    }
    
    @ViewBuilder
    private func mentalModelSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        if !primer.anchor.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("sparkles", size: 18)
                        .foregroundColor(theme.primary)
                    Text("The Mental Model")
                        .font(DS.Typography.headline)
                        .tracking(tightTracking)
                        .foregroundStyle(theme.onSurface)
                }
                
                Text(primer.anchor)
                    .font(DS.Typography.body)
                    .tracking(tightTracking)
                    .foregroundStyle(theme.onSurface)
                    .lineSpacing(6)
                    .padding(DS.Spacing.lg)
                    .background(theme.surfaceVariant)
                    .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private func deepLogicSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        if !primer.mechanism.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("gearshape.fill", size: 18)
                        .foregroundColor(theme.primary)
                    Text("The Deep Logic")
                        .font(DS.Typography.headline)
                        .tracking(tightTracking)
                        .foregroundStyle(theme.onSurface)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(Array(primer.mechanism.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(DS.Typography.body)
                            .tracking(tightTracking)
                            .foregroundStyle(theme.onSurface)
                            .lineSpacing(6)
                    }
                }
                .padding(DS.Spacing.lg)
                .background(theme.surfaceVariant)
                .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private func lensSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        if !primer.lensSee.isEmpty || !primer.lensFeel.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("viewfinder", size: 18)
                        .foregroundColor(theme.primary)
                    Text("The Lens")
                        .font(DS.Typography.headline)
                        .tracking(tightTracking)
                        .foregroundStyle(theme.onSurface)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if !primer.lensSee.isEmpty {
                        lensChip(title: "When you see", cue: primer.lensSee, reason: primer.lensSeeWhy)
                    }
                    if !primer.lensFeel.isEmpty {
                        lensChip(title: "When you feel", cue: primer.lensFeel, reason: primer.lensFeelWhy)
                    }
                }
            }
        }
    }
    
    private func lensChip(title: String, cue: String, reason: String) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.captionEmphasized)
                    .tracking(tightTracking)
                    .foregroundStyle(theme.onSurface)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(theme.onSurface.opacity(0.08))
                    .cornerRadius(999)
                Text(cue)
                    .font(DS.Typography.body)
                    .tracking(tightTracking)
                    .foregroundStyle(theme.onSurface)
                Spacer()
            }
            if !reason.isEmpty {
                Text(reason)
                    .font(DS.Typography.caption)
                    .tracking(tightTracking)
                    .foregroundStyle(theme.onSurface.opacity(0.7))
                    .lineLimit(3)
            }
        }
        .padding(DS.Spacing.md)
        .background(theme.surfaceVariant)
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func rabbitHoleSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        if !primer.rabbitHole.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("magnifyingglass", size: 18)
                        .foregroundColor(theme.primary)
                    Text("The Rabbit Hole")
                        .font(DS.Typography.headline)
                        .tracking(tightTracking)
                        .foregroundStyle(theme.onSurface)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(primer.rabbitHole, id: \.id) { item in
                        Button(action: { openSearch(for: item) }) {
                            let displayQuery = item.query
                                .replacingOccurrences(of: "\"", with: "")
                                .replacingOccurrences(of: "“", with: "")
                                .replacingOccurrences(of: "”", with: "")
                                .replacingOccurrences(of: ",", with: "")
                                .components(separatedBy: .whitespacesAndNewlines)
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(item.label.displayName)
                                    .font(DS.Typography.captionEmphasized)
                                    .tracking(tightTracking)
                                    .foregroundStyle(theme.onSurface.opacity(0.75))
                                    .padding(.horizontal, DS.Spacing.sm)
                                    .padding(.vertical, DS.Spacing.xs)
                                    .background(theme.onSurface.opacity(0.08))
                                    .cornerRadius(999)
                                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                                    Text(displayQuery)
                                        .font(DS.Typography.body)
                                        .tracking(tightTracking)
                                        .foregroundStyle(theme.onSurface)
                                        .lineLimit(2)
                                    Spacer()
                                    DSIcon("arrow.up.right.square", size: 16)
                                        .foregroundColor(theme.onSurface.opacity(0.8))
                                }
                            }
                            .padding(.vertical, DS.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(theme.surfaceVariant)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func legacyContentStack(_ primer: Primer) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            thesisSection(primer)
            storySection(primer)
            examplesSection(primer)
            useItWhenSection(primer)
            howToApplySection(primer)
            edgesAndLimitsSection(primer)
            furtherLearningSection(primer)
            legacyFallbackContent(primer)
        }
    }
    
    
    @ViewBuilder
    private func storySection(_ primer: Primer) -> some View {
        if !primer.story.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("book.fill", size: 18)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).primary)
                    Text("Story")
                        .font(DS.Typography.headline)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Colors.black)
                }
                
                Text(primer.story)
                    .font(DS.Typography.body)
                    .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                    .lineSpacing(4)
                    .themedCard()
            }
        }
    }

    @ViewBuilder
    private func examplesSection(_ primer: Primer) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSIcon("list.bullet", size: 18)
                    .foregroundColor(theme.primary)
                Text("Examples")
                    .font(DS.Typography.headline)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Colors.black)
            }

            // Always show at least the first example if available
            if let first = primer.examples.first, !first.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    exampleRow(first)
                    if showAllExamples && primer.examples.count > 1 {
                        ForEach(Array(primer.examples.dropFirst()), id: \.self) { ex in
                            exampleRow(ex)
                        }
                    }
                }
                .themedCard()
            } else {
                // No examples yet: show a subtle note
                Text("No examples yet. Load more to see scenarios.")
                    .font(DS.Typography.body)
                    .foregroundStyle(theme.onSurface.opacity(0.7))
                    .themedCard()
            }

            HStack(spacing: DS.Spacing.md) {
                if primer.examples.count > 1 {
                    Button(action: { showAllExamples.toggle() }) {
                        HStack {
                            DSIcon(showAllExamples ? "chevron.up" : "chevron.down", size: 14)
                            Text(showAllExamples ? "Hide extra examples" : "Show \(primer.examples.count - 1) more examples")
                                .font(DS.Typography.caption)
                        }
                    }
                    .dsTertiaryButton()
                }

                Spacer()

                Button(action: { loadMoreExamples() }) {
                    HStack {
                        if isLoadingMoreExamples {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                                .scaleEffect(0.8)
                        } else {
                            DSIcon("plus", size: 14)
                        }
                        Text(isLoadingMoreExamples ? "Loading…" : "Load 2 more examples")
                            .font(DS.Typography.caption)
                    }
                }
                .dsTertiaryButton()
                .disabled(isLoadingMoreExamples)
            }
        }
    }

    private func exampleRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.xs) {
            DSIcon("sparkles", size: 14)
                .padding(.top, 2)
            Text(text)
                .font(DS.Typography.body)
                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func useItWhenSection(_ primer: Primer) -> some View {
        if !primer.useItWhen.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("clock.fill", size: 18)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).primary)
                    Text("Use it when...")
                        .font(DS.Typography.headline)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Colors.black)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(primer.useItWhen, id: \.self) { cue in
                        HStack(alignment: .top, spacing: DS.Spacing.xs) {
                            DSIcon("checkmark.circle.fill", size: 14)
                                .padding(.top, 2)
                            Text(cue)
                                .font(DS.Typography.body)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                            Spacer()
                        }
                    }
                }
                .themedCard()
            }
        }
    }
    
    @ViewBuilder
    private func howToApplySection(_ primer: Primer) -> some View {
        if !primer.howToApply.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("gear.circle.fill", size: 18)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).primary)
                    Text("How to apply")
                        .font(DS.Typography.headline)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Colors.black)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(Array(primer.howToApply.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: DS.Spacing.xs) {
                            ZStack {
                                Rectangle()
                                    .fill(themeManager.currentTokens(for: colorScheme).primary)
                                    .frame(width: 20, height: 20)
                                Text("\(index + 1)")
                                    .font(DS.Typography.small)
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onPrimary)
                            }
                            Text(step)
                                .font(DS.Typography.body)
                                .foregroundStyle(themeManager.currentTokens(for: colorScheme).onSurface)
                            Spacer()
                        }
                    }
                }
                .themedCard()
            }
        }
    }
    
    @ViewBuilder
    private func edgesAndLimitsSection(_ primer: Primer) -> some View {
        if !primer.edgesAndLimits.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("exclamationmark.triangle.fill", size: 18)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).primary)
                    Text("Edges & Limits")
                        .font(DS.Typography.headline)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Colors.black)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(primer.edgesAndLimits, id: \.self) { limit in
                        HStack(alignment: .top, spacing: DS.Spacing.xs) {
                            DSIcon("minus.circle.fill", size: 14)
                                .padding(.top, 2)
                            Text(limit)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.primaryText)
                            Spacer()
                        }
                    }
                }
                .dsSubtleCard()
            }
        }
    }
    
    @ViewBuilder
    private func furtherLearningSection(_ primer: Primer) -> some View {
        let linkItems = (primer.links ?? []).sorted { $0.createdAt < $1.createdAt }
        if !linkItems.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    DSIcon("link.circle.fill")
                    Text("Further Learning")
                        .font(DS.Typography.headline)
                        .tracking(tightTracking)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(linkItems, id: \.id) { item in
                        Button(action: {
                            openURL(item.url)
                        }) {
                            HStack {
                                DSIcon("link", size: 14)
                                Text(item.title)
                                    .font(DS.Typography.body)
                                    .tracking(tightTracking)
                                    .foregroundStyle(DS.Colors.primaryText)
                                Spacer()
                                DSIcon("arrow.up.right", size: 14)
                            }
                            .padding(.vertical, DS.Spacing.sm)
                            .padding(.horizontal, DS.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .background(themeManager.currentTokens(for: colorScheme).surfaceVariant)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func legacyFallbackContent(_ primer: Primer) -> some View {
        // Fallback to legacy fields if new fields are empty
        if primer.thesis.isEmpty && !primer.overview.isEmpty {
            Group {
                // Overview Section (Legacy)
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Overview")
                        .font(DS.Typography.headline)
                    
                    Text(primer.overview)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.primaryText)
                        .lineSpacing(4)
                }
                
                // Key Nuances Section (Legacy)
                if !primer.keyNuances.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("Key Nuances")
                            .font(DS.Typography.headline)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            ForEach(primer.keyNuances, id: \.self) { nuance in
                                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                                    DSIcon("circle.fill", size: 8)
                                        .padding(.top, 6)
                                    Text(nuance)
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.primaryText)
                                }
                            }
                        }
                    }
                }
                
                // Dig Deeper Section (Legacy)
                if !primer.digDeeperLinks.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("Dig Deeper")
                            .font(DS.Typography.headline)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            ForEach(primer.digDeeperLinks, id: \.title) { link in
                                Button(action: {
                                    openURL(link.url)
                                }) {
                                    HStack {
                                        DSIcon("link", size: 14)
                                        Text(link.title)
                                            .font(DS.Typography.body)
                                            .foregroundStyle(DS.Colors.primaryText)
                                            .underline()
                                        Spacer()
                                    }
                                }
                                .dsTertiaryButton()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var refreshButton: some View {
        Button(action: {
            refreshPrimer()
        }) {
            HStack {
                if isRefreshing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                        .scaleEffect(0.8)
                } else {
                    DSIcon("arrow.clockwise", size: 14)
                }
                Text("Refresh Primer")
                    .font(DS.Typography.caption)
                    .tracking(tightTracking)
            }
            .foregroundStyle(DS.Colors.black)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(themeManager.currentTokens(for: colorScheme).surfaceVariant)
        .cornerRadius(10)
        .disabled(isRefreshing)
        .padding(.top, DS.Spacing.md)
    }
    
    // MARK: - Methods
    
    private func hasNewEncodingContent(_ primer: Primer) -> Bool {
        return !primer.shift.isEmpty ||
        !primer.anchor.isEmpty ||
        !primer.mechanism.isEmpty ||
        !primer.lensSee.isEmpty ||
        !primer.lensFeel.isEmpty ||
        !primer.rabbitHole.isEmpty
    }
    
    private func loadPrimer() {
        isLoading = true
        errorMessage = nil
        
        // Ensure primerService is initialized
        guard let service = primerService else {
            errorMessage = "Primer service not initialized"
            isLoading = false
            return
        }
        
        // Check if primer already exists
        if let existingPrimer = service.getPrimer(for: idea) {
            primer = existingPrimer
            isLoading = false
            return
        }
        
        // Generate new primer
        Task {
            do {
                let newPrimer = try await service.generatePrimer(for: idea)
                await MainActor.run {
                    primer = newPrimer
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate primer: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func refreshPrimer() {
        isRefreshing = true
        
        // Ensure primerService is initialized
        guard let service = primerService else {
            errorMessage = "Primer service not initialized"
            isRefreshing = false
            return
        }
        
        Task {
            do {
                let newPrimer = try await service.refreshPrimer(for: idea)
                await MainActor.run {
                    primer = newPrimer
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to refresh primer: \(error.localizedDescription)"
                    isRefreshing = false
                }
            }
        }
    }

    private func loadMoreExamples(count: Int = 2) {
        isLoadingMoreExamples = true
        guard let service = primerService, let currentPrimer = primer else {
            isLoadingMoreExamples = false
            return
        }
        Task {
            do {
                let updated = try await service.appendExamples(to: currentPrimer, for: idea, count: count)
                await MainActor.run {
                    self.primer = updated
                    self.isLoadingMoreExamples = false
                    self.showAllExamples = true // reveal newly loaded examples
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load examples: \(error.localizedDescription)"
                    self.isLoadingMoreExamples = false
                }
            }
        }
    }
    
    private func openSearch(for item: RabbitHoleItem) {
        let sanitized = item.query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let query = sanitized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString: String
        switch item.label {
        case .visual:
            urlString = "https://www.youtube.com/results?search_query=\(query)"
        case .debate, .counter, .other:
            urlString = "https://www.google.com/search?q=\(query)"
        }
        openURL(urlString)
    }
    
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { 
            print("Invalid URL: \(urlString)")
            return 
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url) { success in
                if !success {
                    print("Failed to open URL: \(urlString)")
                }
            }
        } else {
            print("Cannot open URL: \(urlString)")
        }
    }
}

 
