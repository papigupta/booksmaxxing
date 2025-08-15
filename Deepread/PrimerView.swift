import SwiftUI
import SwiftData

struct PrimerView: View {
    let idea: Idea
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var primerService: PrimerService?
    @State private var primer: Primer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    
    init(idea: Idea, openAIService: OpenAIService) {
        self.idea = idea
        self.openAIService = openAIService
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                DSDivider()
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
        .onAppear {
            // Initialize primerService with the correct modelContext
            primerService = PrimerService(openAIService: openAIService, modelContext: modelContext)
            loadPrimer()
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(idea.bookTitle)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text("Primer: \(idea.title)")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            loadingView
        } else if let error = errorMessage {
            errorView(error)
        } else if let primer = primer {
            primerContentView(primer)
        }
    }
    
    private var loadingView: some View {
        DSLoadingView(message: "Generating your primer...")
    }
    
    private func errorView(_ error: String) -> some View {
        DSErrorView(
            title: "Error",
            message: error,
            retryAction: { loadPrimer() }
        )
    }
    
    private func primerContentView(_ primer: Primer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                thesisSection(primer)
                storySection(primer)
                useItWhenSection(primer)
                howToApplySection(primer)
                edgesAndLimitsSection(primer)
                oneLineRecallSection(primer)
                furtherLearningSection(primer)
                legacyFallbackContent(primer)
                refreshButton
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
    }
    
    @ViewBuilder
    private func thesisSection(_ primer: Primer) -> some View {
        if !primer.thesis.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    DSIcon("lightbulb.fill")
                    Text("Thesis")
                        .font(DS.Typography.headline)
                }
                
                Text(primer.thesis)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.primaryText)
                    .lineSpacing(4)
                    .dsCard()
            }
        }
    }
    
    
    @ViewBuilder
    private func storySection(_ primer: Primer) -> some View {
        if !primer.story.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    DSIcon("book.fill")
                    Text("Story")
                        .font(DS.Typography.headline)
                }
                
                Text(primer.story)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.primaryText)
                    .lineSpacing(4)
                    .dsSubtleCard()
            }
        }
    }
    
    @ViewBuilder
    private func useItWhenSection(_ primer: Primer) -> some View {
        if !primer.useItWhen.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    DSIcon("clock.fill")
                    Text("Use it when...")
                        .font(DS.Typography.headline)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(primer.useItWhen, id: \.self) { cue in
                        HStack(alignment: .top, spacing: DS.Spacing.xs) {
                            DSIcon("checkmark.circle.fill", size: 14)
                                .padding(.top, 2)
                            Text(cue)
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
    private func howToApplySection(_ primer: Primer) -> some View {
        if !primer.howToApply.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    DSIcon("gear.circle.fill")
                    Text("How to apply")
                        .font(DS.Typography.headline)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(Array(primer.howToApply.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: DS.Spacing.xs) {
                            ZStack {
                                Rectangle()
                                    .fill(DS.Colors.black)
                                    .frame(width: 20, height: 20)
                                Text("\(index + 1)")
                                    .font(DS.Typography.small)
                                    .fontWeight(.bold)
                                    .foregroundColor(DS.Colors.white)
                            }
                            Text(step)
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
    private func edgesAndLimitsSection(_ primer: Primer) -> some View {
        if !primer.edgesAndLimits.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    DSIcon("exclamationmark.triangle.fill")
                    Text("Edges & Limits")
                        .font(DS.Typography.headline)
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
    private func oneLineRecallSection(_ primer: Primer) -> some View {
        if !primer.oneLineRecall.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    DSIcon("quote.bubble.fill")
                    Text("One-line Recall")
                        .font(DS.Typography.headline)
                }
                
                Text("\"\(primer.oneLineRecall)\"")
                    .font(DS.Typography.body)
                    .italic()
                    .foregroundColor(DS.Colors.primaryText)
                    .lineSpacing(4)
                    .dsCard(borderColor: DS.Colors.black)
            }
        }
    }
    
    @ViewBuilder
    private func furtherLearningSection(_ primer: Primer) -> some View {
        if !primer.furtherLearning.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    DSIcon("link.circle.fill")
                    Text("Further Learning")
                        .font(DS.Typography.headline)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(primer.furtherLearning, id: \.title) { link in
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
                                DSIcon("arrow.up.right", size: 14)
                            }
                            .padding(.vertical, DS.Spacing.xxs)
                        }
                        .dsTertiaryButton()
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
            }
            .foregroundStyle(DS.Colors.black)
        }
        .dsTertiaryButton()
        .disabled(isRefreshing)
        .padding(.top, DS.Spacing.md)
    }
    
    // MARK: - Methods
    
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