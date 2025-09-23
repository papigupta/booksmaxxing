import SwiftUI
import SwiftData
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Idea Responses View
@MainActor
struct IdeaResponsesView: View {
    let idea: Idea
    
    @Environment(\.modelContext) private var modelContext
    @State private var attemptsByLane: [Lane: LaneAttempts] = [:]
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    
    enum Lane: Int, CaseIterable { case curveball = 0, spfu, review, fresh }
    
    struct AttemptItem: Identifiable {
        let id: UUID
        let response: QuestionResponse
        let question: Question
        let lane: Lane
        var isOEQ: Bool { question.type == .openEnded }
        var answeredAt: Date { response.answeredAt }
    }
    
    struct LaneAttempts {
        var oeq: [AttemptItem] = []
        var mcq: [AttemptItem] = []
    }
    
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(idea.title)
                    .font(DS.Typography.headline)
                    .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface)
                    .lineLimit(2)
                Spacer()
            }
            .padding([.horizontal, .top], DS.Spacing.lg)
            
            DSDivider()
            
            if isLoading {
                VStack(spacing: DS.Spacing.md) {
                    ProgressView()
                    Text("Loading responses…")
                        .font(DS.Typography.caption)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: DS.Spacing.md) {
                    Text("Unable to load responses")
                        .font(DS.Typography.bodyBold)
                    Text(errorMessage)
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                    
                    Button("Retry") { Task { await loadData() } }
                        .dsSecondaryButton()
                }
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if attemptsByLane.isEmpty || totalCount == 0 {
                // Empty state
                VStack(spacing: DS.Spacing.md) {
                    Text("No responses yet")
                        .font(DS.Typography.headline)
                        .foregroundColor(DS.Colors.primaryText)
                    Text("Start a practice session to capture your insights.")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        laneSection(.curveball, title: "Curveball")
                        laneSection(.spfu, title: "Spaced Follow‑Up")
                        laneSection(.review, title: "Review")
                        laneSection(.fresh, title: "Fresh")
                    }
                    .padding(DS.Spacing.lg)
                }
            }
        }
        .task { await loadData() }
        .navigationTitle("Responses")
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.surface.ignoresSafeArea())
    }
    
    private var totalCount: Int {
        attemptsByLane.values.reduce(0) { $0 + $1.oeq.count + $1.mcq.count }
    }
    
    private func laneSection(_ lane: Lane, title: String) -> some View {
        let data = attemptsByLane[lane] ?? LaneAttempts()
        let hasOEQ = !data.oeq.isEmpty
        let hasMCQ = !data.mcq.isEmpty
        return Group {
            if hasOEQ || hasMCQ {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text(title)
                        .font(DS.Typography.bodyBold)
                        .foregroundColor(DS.Colors.primaryText)
                    
                    // OEQ first
                    if hasOEQ {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            ForEach(data.oeq.sorted(by: { $0.answeredAt > $1.answeredAt })) { item in
                                OEQCard(attempt: item)
                            }
                        }
                    }
                    
                    // MCQ collapsed group (v1 simple)
                    if hasMCQ {
                        MCQSection(items: data.mcq.sorted(by: { $0.answeredAt > $1.answeredAt }))
                    }
                }
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 1) Fetch all questions for this idea
            let targetId = idea.id // capture as constant; don't reference another model keypath in predicate
            let qDescriptor = FetchDescriptor<Question>(
                predicate: #Predicate<Question> { $0.ideaId == targetId }
            )
            let questions = try modelContext.fetch(qDescriptor)
            
            // 2) Flatten responses into AttemptItems
            // Prefer direct relationship; also backfill by looking up attempts linked to the same test
            var buckets: [Lane: LaneAttempts] = [:]
            var needsSave = false
            for q in questions {
                let lane = inferLane(for: q)

                // Directly linked responses
                var linked = q.responses ?? []

                // Fallback: scan attempts on the test and match by questionId
                if let testAttempts = q.test?.attempts {
                    let extras = testAttempts.compactMap { $0.response(for: q.id) }
                    // Deduplicate by id
                    for e in extras where linked.contains(where: { $0.id == e.id }) == false {
                        linked.append(e)
                        // Backfill inverse relationship if missing
                        if e.question == nil {
                            e.question = q
                            needsSave = true
                        }
                        if q.responses == nil { q.responses = [] }
                        if q.responses?.contains(where: { $0.id == e.id }) == false {
                            q.responses?.append(e)
                            needsSave = true
                        }
                    }
                }

                for r in linked {
                    let item = AttemptItem(id: r.id, response: r, question: q, lane: lane)
                    if item.isOEQ {
                        buckets[lane, default: LaneAttempts()].oeq.append(item)
                    } else {
                        buckets[lane, default: LaneAttempts()].mcq.append(item)
                    }
                }
            }

            attemptsByLane = buckets
            if needsSave { try? modelContext.save() }
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
    
    private func inferLane(for q: Question) -> Lane {
        if q.isCurveball { return .curveball }
        if q.isSpacedFollowUp { return .spfu }
        if (q.test?.testType.lowercased() == "review") { return .review }
        return .fresh
    }
}

// MARK: - OEQ Card
private struct OEQCard: View {
    let attempt: IdeaResponsesView.AttemptItem
    @State private var expanded: Bool = false
    @State private var copied: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(formattedDate(attempt.answeredAt))
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
                Spacer()
                Text(attempt.question.bloomCategory.rawValue)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.secondaryText)
            }
            
            // Prompt snapshot
            Text(attempt.question.questionText)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.primaryText)
                .lineLimit(expanded ? nil : 3)
            
            // User answer
            Text(attempt.response.userAnswer)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.primaryText)
                .lineLimit(expanded ? nil : 6)
            
            HStack(spacing: DS.Spacing.sm) {
                Button(action: copyAnswer) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(DS.Typography.captionBold)
                }
                .dsSmallButton()

                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Typography.captionBold)
                }
                .dsSmallButton()

                Spacer()

                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(DS.Typography.captionBold)
                }
                .dsSmallButton()
            }
        }
        .padding(DS.Spacing.md)
        .themedCard()
    }
    
    private var shareText: String {
        let prompt = attempt.question.questionText
        let answer = attempt.response.userAnswer
        return "Prompt: \n\(prompt)\n\nMy answer:\n\(answer)"
    }
    
    private func copyAnswer() {
        #if canImport(UIKit)
        UIPasteboard.general.string = attempt.response.userAnswer
        #endif
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - MCQ Section (collapsed by default)
private struct MCQSection: View {
    let items: [IdeaResponsesView.AttemptItem]
    @State private var expanded = false
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button(action: { withAnimation { expanded.toggle() } }) {
                HStack {
                    Label(expanded ? "Hide MCQ Attempts" : "Show MCQ Attempts", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(DS.Typography.captionBold)
                    Spacer()
                    Text("\(items.count)")
                        .font(DS.Typography.caption)
                        .foregroundColor(themeManager.currentTokens(for: colorScheme).onSurface.opacity(0.7))
                }
            }
            .themeSecondaryButton()
            
            if expanded {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            HStack {
                                Text(formattedDate(item.answeredAt))
                                    .font(DS.Typography.caption)
                                    .foregroundColor(DS.Colors.secondaryText)
                                Spacer()
                                Text(item.question.bloomCategory.rawValue)
                                    .font(DS.Typography.caption)
                                    .foregroundColor(DS.Colors.secondaryText)
                            }
                            Text(item.question.questionText)
                                .font(DS.Typography.body)
                                .foregroundColor(DS.Colors.primaryText)
                                .lineLimit(3)

                            // Attempt outcome summary in words
                            if let correctIndex = (item.question.correctAnswers ?? []).first {
                                let picked: Int? = {
                                    if let v = Int(item.response.userAnswer) { return v }
                                    if let data = Data(base64Encoded: item.response.userAnswer),
                                       let arr = try? JSONDecoder().decode([Int].self, from: data),
                                       let first = arr.first { return first }
                                    if let data = item.response.userAnswer.data(using: .utf8),
                                       let arr = try? JSONDecoder().decode([Int].self, from: data),
                                       let first = arr.first { return first }
                                    return nil
                                }()

                                let options = item.question.options ?? []
                                let correctText = (correctIndex < options.count) ? options[correctIndex] : "Option \(correctIndex + 1)"
                                if let picked = picked {
                                    let pickedText = (picked < options.count) ? options[picked] : "Option \(picked + 1)"
                                    if picked == correctIndex {
                                        Text("Correct: \(correctText)")
                                            .font(DS.Typography.captionBold)
                                            .foregroundColor(.green)
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Correct: \(correctText)")
                                                .font(DS.Typography.captionBold)
                                                .foregroundColor(.green)
                                            Text("Your answer: \(pickedText)")
                                                .font(DS.Typography.captionBold)
                                                .foregroundColor(.red)
                                        }
                                    }
                                } else {
                                    Text("Correct: \(correctText)")
                                        .font(DS.Typography.captionBold)
                                        .foregroundColor(DS.Colors.secondaryText)
                                }
                            }
                        }
                        .padding(DS.Spacing.md)
                        .background(themeManager.currentTokens(for: colorScheme).surfaceVariant)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(themeManager.currentTokens(for: colorScheme).outline, lineWidth: DS.BorderWidth.thin))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Helpers
private func formattedDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
}
