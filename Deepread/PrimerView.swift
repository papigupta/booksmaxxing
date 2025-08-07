import SwiftUI
import SwiftData

struct PrimerView: View {
    let idea: Idea
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var primerService: PrimerService
    @State private var primer: Primer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    
    init(idea: Idea, openAIService: OpenAIService) {
        self.idea = idea
        self.openAIService = openAIService
        // Initialize with a temporary context, will be updated in onAppear
        let tempContext = try! ModelContainer(for: Idea.self).mainContext
        self._primerService = StateObject(wrappedValue: PrimerService(openAIService: openAIService, modelContext: tempContext))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
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
                
                Divider()
                
                // Content
                if isLoading {
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
                } else if let error = errorMessage {
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
                } else if let primer = primer {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Overview Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Overview")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text(primer.overview)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)
                            }
                            
                            // Key Nuances Section
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
                            
                            // Dig Deeper Section
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
                            
                            // Refresh Button
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
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
            // Update the primerService with the correct modelContext
            primerService.updateModelContext(modelContext)
            loadPrimer()
        }
    }
    
    // MARK: - Methods
    
    private func loadPrimer() {
        isLoading = true
        errorMessage = nil
        
        // Check if primer already exists
        if let existingPrimer = primerService.getPrimer(for: idea) {
            primer = existingPrimer
            isLoading = false
            return
        }
        
        // Generate new primer
        Task {
            do {
                let newPrimer = try await primerService.generatePrimer(for: idea)
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
        
        Task {
            do {
                let newPrimer = try await primerService.refreshPrimer(for: idea)
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