import SwiftUI

struct ResponseCard: View {
    let response: UserResponse
    let levelName: String
    @State private var isExpanded = false
    @State private var showAllResponses = false
    @State private var allResponses: [UserResponse] = []
    @Environment(\.modelContext) private var modelContext
    
    private var userResponseService: UserResponseService {
        UserResponseService(modelContext: modelContext)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Level \(response.level): \(levelName)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if response.hasEvaluation, let score = response.score {
                    Text("\(score)/10")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(response.prompt)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            // Response
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Response")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(response.response)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(isExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
            
            // Evaluation Results (if available)
            if response.hasEvaluation {
                VStack(alignment: .leading, spacing: 12) {
                    // Score
                    if let score = response.score {
                        HStack {
                            Text("Score: \(score)/10")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            ProgressView(value: Double(score), total: 10.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                .frame(width: 100)
                        }
                    }
                    
                    // Strengths
                    if !response.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strengths")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                            
                            ForEach(response.strengths, id: \.self) { strength in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text(strength)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    
                    // Improvements
                    if !response.improvements.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Areas for Improvement")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            
                            ForEach(response.improvements, id: \.self) { improvement in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text(improvement)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    
                    // Silver Bullet
                    if let silverBullet = response.silverBullet {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Author's Insight")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                            
                            Text(silverBullet)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Show Other Responses Button (if there are multiple responses for this level)
            if showAllResponses && !allResponses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Other Attempts")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(allResponses.filter { $0.id != response.id }, id: \.id) { otherResponse in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Attempt on \(formatDate(otherResponse.timestamp))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if let score = otherResponse.score {
                                    Text("\(score)/10")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(otherResponse.response)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    }
                }
            }
            
            // Action Buttons
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Show Other Responses Button
                if allResponses.count > 1 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showAllResponses.toggle()
                        }
                    }) {
                        Text(showAllResponses ? "Hide Others" : "Show \(allResponses.count - 1) Other\(allResponses.count > 2 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .frame(minHeight: isExpanded ? nil : 320)
        .clipped()
        .onAppear {
            loadAllResponses()
        }
    }
    
    private func loadAllResponses() {
        Task {
            do {
                let responses = try await userResponseService.getAllResponsesForLevel(ideaId: response.ideaId, level: response.level)
                await MainActor.run {
                    self.allResponses = responses
                }
            } catch {
                print("DEBUG: Failed to load all responses: \(error)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
} 