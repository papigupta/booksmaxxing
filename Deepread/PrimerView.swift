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
                Divider()
                contentView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(idea.bookTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text("Primer: \(idea.title)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
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
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating your primer...")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Error")
                .font(.headline)
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                loadPrimer()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func primerContentView(_ primer: Primer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private func thesisSection(_ primer: Primer) -> some View {
        if !primer.thesis.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    Text("Thesis")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(primer.thesis)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
        }
    }
    
    
    @ViewBuilder
    private func storySection(_ primer: Primer) -> some View {
        if !primer.story.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.purple)
                        .font(.title3)
                    Text("Story")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(primer.story)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.05))
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
    
    @ViewBuilder
    private func useItWhenSection(_ primer: Primer) -> some View {
        if !primer.useItWhen.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    Text("Use it when...")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(primer.useItWhen, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(cue)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.05))
                )
            }
        }
    }
    
    @ViewBuilder
    private func howToApplySection(_ primer: Primer) -> some View {
        if !primer.howToApply.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "gear.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    Text("How to apply")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(primer.howToApply.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 20, height: 20)
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            Text(step)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.05))
                )
            }
        }
    }
    
    @ViewBuilder
    private func edgesAndLimitsSection(_ primer: Primer) -> some View {
        if !primer.edgesAndLimits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                    Text("Edges & Limits")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(primer.edgesAndLimits, id: \.self) { limit in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(limit)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.05))
                )
            }
        }
    }
    
    @ViewBuilder
    private func oneLineRecallSection(_ primer: Primer) -> some View {
        if !primer.oneLineRecall.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "quote.bubble.fill")
                        .foregroundColor(.purple)
                        .font(.title3)
                    Text("One-line Recall")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text("\"\(primer.oneLineRecall)\"")
                    .font(.title3)
                    .italic()
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.05))
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }
    
    @ViewBuilder
    private func furtherLearningSection(_ primer: Primer) -> some View {
        if !primer.furtherLearning.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Text("Further Learning")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(primer.furtherLearning, id: \.title) { link in
                        Button(action: {
                            openURL(link.url)
                        }) {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                                Text(link.title)
                                    .font(.body)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Overview")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(primer.overview)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                }
                
                // Key Nuances Section (Legacy)
                if !primer.keyNuances.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Key Nuances")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(primer.keyNuances, id: \.self) { nuance in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                        .padding(.top, 4)
                                    Text(nuance)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                
                // Dig Deeper Section (Legacy)
                if !primer.digDeeperLinks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dig Deeper")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(primer.digDeeperLinks, id: \.title) { link in
                                Button(action: {
                                    openURL(link.url)
                                }) {
                                    HStack {
                                        Image(systemName: "link")
                                            .foregroundStyle(.blue)
                                            .font(.caption)
                                        Text(link.title)
                                            .font(.body)
                                            .foregroundStyle(.blue)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
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
                        .scaleEffect(0.8)
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                Text("Refresh Primer")
                    .font(.caption)
            }
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .padding(.top, 16)
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