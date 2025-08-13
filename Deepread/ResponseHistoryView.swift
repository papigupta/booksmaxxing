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
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading your learning history...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
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
                            loadResponseHistory()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if bestResponses.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "text.book.closed")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Responses Yet")
                            .font(.headline)
                        Text("You haven't completed any levels for this idea yet.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
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
                        .padding(16)
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