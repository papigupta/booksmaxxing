import SwiftUI

struct ResponseHistoryView: View {
    let idea: Idea
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var bestResponses: [Int: UserResponse] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var userResponseService: UserResponseService {
        UserResponseService(modelContext: modelContext)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                            .scaleEffect(1.2)
                        Text("Loading your learning history...")
                            .font(DS.Typography.body)
                            .foregroundColor(DS.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: DS.Spacing.lg) {
                        DSIcon("exclamationmark.triangle", size: 48)
                        Text("Error")
                            .font(DS.Typography.headline)
                            .foregroundColor(DS.Colors.primaryText)
                        Text(error)
                            .font(DS.Typography.body)
                            .foregroundColor(DS.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            loadResponseHistory()
                        }
                        .dsSecondaryButton()
                        .frame(width: 160)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(DS.Spacing.xl)
                } else if bestResponses.isEmpty {
                    VStack(spacing: DS.Spacing.lg) {
                        DSIcon("text.book.closed", size: 48)
                        Text("No Responses Yet")
                            .font(DS.Typography.headline)
                            .foregroundColor(DS.Colors.primaryText)
                        Text("You haven't completed any levels for this idea yet.")
                            .font(DS.Typography.body)
                            .foregroundColor(DS.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(DS.Spacing.xl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.md) {
                            // Sort levels (L1, L2, L3, etc.)
                            let sortedLevels = bestResponses.keys.sorted()
                            
                            ForEach(sortedLevels, id: \.self) { level in
                                if let response = bestResponses[level] {
                                    ResponseCard(
                                        response: response,
                                        levelName: getLevelName(for: level)
                                    )
                                }
                            }
                        }
                        .padding(DS.Spacing.md)
                    }
                }
            }
            .navigationTitle("Learning History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .dsTertiaryButton()
                }
            }
        }
        .onAppear {
            loadResponseHistory()
        }
    }
    
    private func loadResponseHistory() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let responses = try await userResponseService.getBestResponsesByLevel(for: idea.id)
                await MainActor.run {
                    self.bestResponses = responses
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load response history: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func getLevelName(for level: Int) -> String {
        switch level {
        case 1: return "Why Care"
        case 2: return "When Use"
        case 3: return "How Wield"
        default: return "Level \(level)"
        }
    }
} 