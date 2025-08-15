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
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header
            HStack {
                Text("Level \(response.level): \(levelName)")
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.primaryText)
                
                Spacer()
                
                if response.hasEvaluation, let starScore = response.starScore {
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(1...3, id: \.self) { star in
                            DSIcon(star <= starScore ? "star.fill" : "star", size: 12)
                                .foregroundColor(star <= starScore ? DS.Colors.black : DS.Colors.gray300)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(DS.Colors.gray50)
                    .overlay(
                        Rectangle()
                            .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
                    )
                }
            }
            
            // Prompt
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Prompt")
                    .font(DS.Typography.captionBold)
                    .foregroundColor(DS.Colors.secondaryText)
                
                Text(response.prompt)
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.primaryText)
            }
            
            // Response
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Your Response")
                    .font(DS.Typography.captionBold)
                    .foregroundColor(DS.Colors.secondaryText)
                
                Text(response.response)
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.primaryText)
                    .lineLimit(isExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
            
            // Evaluation Results (if available)
            if response.hasEvaluation {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    // Star Score
                    if let starScore = response.starScore {
                        HStack {
                            Text("Rating:")
                                .font(DS.Typography.captionBold)
                                .foregroundColor(DS.Colors.primaryText)
                            
                            HStack(spacing: DS.Spacing.xxs) {
                                ForEach(1...3, id: \.self) { star in
                                    DSIcon(star <= starScore ? "star.fill" : "star", size: 14)
                                        .foregroundColor(star <= starScore ? DS.Colors.black : DS.Colors.gray300)
                                }
                            }
                            
                            Text(getStarDescription(for: starScore))
                                .font(DS.Typography.small)
                                .foregroundColor(DS.Colors.secondaryText)
                            
                            Spacer()
                        }
                    }
                    
                    // Silver Bullet
                    if let silverBullet = response.silverBullet {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Author's Insight")
                                .font(DS.Typography.captionBold)
                                .foregroundColor(DS.Colors.black)
                            
                            Text(silverBullet)
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.primaryText)
                                .padding(DS.Spacing.xs)
                                .background(DS.Colors.gray50)
                                .overlay(
                                    Rectangle()
                                        .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
                                )
                        }
                    }
                }
            }
            
            // Show Other Responses Button (if there are multiple responses for this level)
            if showAllResponses && !allResponses.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Other Attempts")
                        .font(DS.Typography.captionBold)
                        .foregroundColor(DS.Colors.secondaryText)
                    
                    ForEach(allResponses.filter { $0.id != response.id }, id: \.id) { otherResponse in
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            HStack {
                                Text("Attempt on \(formatDate(otherResponse.timestamp))")
                                    .font(DS.Typography.small)
                                    .foregroundColor(DS.Colors.secondaryText)
                                
                                Spacer()
                                
                                if let starScore = otherResponse.starScore {
                                    HStack(spacing: 1) {
                                        ForEach(1...3, id: \.self) { star in
                                            DSIcon(star <= starScore ? "star.fill" : "star", size: 8)
                                                .foregroundColor(star <= starScore ? DS.Colors.black : DS.Colors.gray300)
                                        }
                                    }
                                }
                            }
                            
                            Text(otherResponse.response)
                                .font(DS.Typography.small)
                                .foregroundColor(DS.Colors.primaryText)
                                .lineLimit(2)
                        }
                        .dsSubtleCard(padding: DS.Spacing.xs)
                    }
                }
            }
            
            DSDivider()
            
            // Action Buttons
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? "Show Less" : "Show More")
                }
                .dsTertiaryButton()
                
                Spacer()
                
                // Show Other Responses Button
                if allResponses.count > 1 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showAllResponses.toggle()
                        }
                    }) {
                        Text(showAllResponses ? "Hide Others" : "Show \(allResponses.count - 1) Other\(allResponses.count > 2 ? "s" : "")")
                    }
                    .dsTertiaryButton()
                }
            }
        }
        .dsCard()
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
    
    private func getStarDescription(for starScore: Int) -> String {
        switch starScore {
        case 1: return "Getting There"
        case 2: return "Solid Grasp"
        case 3: return "Aha! Moment"
        default: return ""
        }
    }
}