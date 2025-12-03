import Foundation
import SwiftData
import OSLog

private struct ParsedPrimer {
    var shift: String = ""
    var anchor: String = ""
    var anchorIsAuthorMetaphor: Bool = false
    var mechanism: [String] = []
    var lensSee: String = ""
    var lensSeeWhy: String = ""
    var lensFeel: String = ""
    var lensFeelWhy: String = ""
    var rabbitHole: [RabbitHoleItem] = []
    
    // Legacy fields for fallback compatibility
    var thesis: String = ""
    var story: String = ""
    var examples: [String] = []
    var useItWhen: [String] = []
    var howToApply: [String] = []
    var edgesAndLimits: [String] = []
    var oneLineRecall: String = ""
    var furtherLearning: [PrimerLink] = []
}

@MainActor
class PrimerService: ObservableObject {
    private let openAIService: OpenAIService
    private var modelContext: ModelContext
    private let logger = Logger(subsystem: "com.booksmaxxing.app", category: "Primer")
    
    init(openAIService: OpenAIService, modelContext: ModelContext) {
        self.openAIService = openAIService
        self.modelContext = modelContext
    }
    
    // MARK: - Model Context Update
    
    func updateModelContext(_ newModelContext: ModelContext) {
        self.modelContext = newModelContext
    }
    
    // MARK: - Primer Generation
    
    func generatePrimer(for idea: Idea) async throws -> Primer {
        let userPrompt = createPrimerPrompt(for: idea)
        let system = "You are an encoding-focused explainer for famous non-fiction. You blend vivid imagery and precise logic to produce dual-coded explanations that feel like the author's voice."

        let primerContent = try await openAIService.chat(
            systemPrompt: system,
            userPrompt: userPrompt,
            model: "gpt-4.1",
            temperature: 0.7,
            maxTokens: 2400
        )
        
        // Parse the response into structured data
        let parsedPrimer = try parsePrimerResponse(primerContent)
        
        // Create and save the primer with new structure
        let primer = Primer(
            ideaId: idea.id,
            shift: parsedPrimer.shift,
            anchor: parsedPrimer.anchor,
            anchorIsAuthorMetaphor: parsedPrimer.anchorIsAuthorMetaphor,
            mechanism: parsedPrimer.mechanism,
            lensSee: parsedPrimer.lensSee,
            lensSeeWhy: parsedPrimer.lensSeeWhy,
            lensFeel: parsedPrimer.lensFeel,
            lensFeelWhy: parsedPrimer.lensFeelWhy,
            rabbitHole: parsedPrimer.rabbitHole,
            thesis: parsedPrimer.thesis,
            story: parsedPrimer.story,
            examples: parsedPrimer.examples,
            useItWhen: parsedPrimer.useItWhen,
            howToApply: parsedPrimer.howToApply,
            edgesAndLimits: parsedPrimer.edgesAndLimits,
            oneLineRecall: parsedPrimer.oneLineRecall,
            furtherLearning: parsedPrimer.furtherLearning
        )
        
        primer.idea = idea
        // Create CloudKit-friendly link items
        var linkItems: [PrimerLinkItem] = []
        for link in parsedPrimer.furtherLearning {
            let item = PrimerLinkItem(title: link.title, url: link.url)
            item.primer = primer
            linkItems.append(item)
            modelContext.insert(item)
        }
        primer.links = linkItems
        modelContext.insert(primer)
        try modelContext.save()
        
        return primer
    }
    
    // MARK: - Primer Retrieval
    
    func getPrimer(for idea: Idea) -> Primer? {
        let ideaId = idea.id
        let descriptor = FetchDescriptor<Primer>(
            predicate: #Predicate<Primer> { primer in
                primer.ideaId == ideaId
            }
        )
        
        do {
            let primers: [Primer] = try modelContext.fetch(descriptor)
            return primers.first
        } catch {
            print("Error fetching primer: \(error)")
            return nil
        }
    }
    
    func refreshPrimer(for idea: Idea) async throws -> Primer {
        // Delete existing primer if it exists
        if let existingPrimer = getPrimer(for: idea) {
            modelContext.delete(existingPrimer)
            try modelContext.save()
        }
        
        // Generate new primer
        return try await generatePrimer(for: idea)
    }
    
    // MARK: - Helper Methods
    
    private func createPrimerPrompt(for idea: Idea) -> String {
        return """
        GOAL: Create a deep-encoding "Primer" for the concept "\(idea.title)" from the book "\(idea.bookTitle)".

        CONTEXT: The user already read it; they need an "Aha!" re-encoding (dual coding + elaboration). You can use accurate book-specific metaphors from your own knowledge; do not fabricate.

        SOURCE MATERIAL: "\(idea.ideaDescription)"

        OUTPUT FORMAT (use these exact headings/labels):

        # The Shift (≤20 words)
        Most people think X, but actually Y.

        # The Anchor (Visual Analogy) (60–80 words)
        Source: <Author metaphor | New analogy>
        Analogy: <vivid analogy text>

        # The Mechanism (The Logic)
        - <mechanism bullet 1>
        - <mechanism bullet 2>
        - <mechanism bullet 3>

        # The Lens (When to see it)
        When you see: <cue> — Why: <brief rationale>
        When you feel: <cue> — Why: <brief rationale>

        # The Rabbit Hole (Curiosity)
        - Debate: <search query for a debate/lecture>
        - Visual: <search query for a visual/animation>
        - Counter: <search query for a counter-argument>

        TONE: Intellectual, slightly provocative, matching the book's authorial voice. No URLs—only queries. Be concrete and specific; avoid generic filler. Total length ≈ 200 words.
        """
    }
    
    private func parsePrimerResponse(_ response: String) throws -> ParsedPrimer {
        let lines = response.components(separatedBy: .newlines)
        var parsed = ParsedPrimer()
        var currentSection = ""
        
        func cleanQuery(_ text: String) -> String {
            let stripped = text
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "“", with: "")
                .replacingOccurrences(of: "”", with: "")
                .replacingOccurrences(of: ",", with: "")
            let squashed = stripped
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return squashed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        func parseLensLine(_ line: String, isFeel: Bool) {
            // Expect "When you see: <cue> — Why: <reason>"
            let parts = line
                .replacingOccurrences(of: "When you see:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "When you feel:", with: "", options: .caseInsensitive)
                .split(separator: "—", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            let cue = parts.first ?? ""
            let reason = parts.count > 1
                ? parts[1].replacingOccurrences(of: "Why:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                : ""
            if isFeel {
                if !cue.isEmpty { parsed.lensFeel = cue }
                if !reason.isEmpty { parsed.lensFeelWhy = reason }
            } else {
                if !cue.isEmpty { parsed.lensSee = cue }
                if !reason.isEmpty { parsed.lensSeeWhy = reason }
            }
        }
        
        func labelFrom(_ text: String) -> RabbitHoleLabel {
            let lower = text.lowercased()
            if lower.contains("debate") { return .debate }
            if lower.contains("visual") { return .visual }
            if lower.contains("counter") { return .counter }
            return .other
        }
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { continue }
            
            // New structure headers
            if trimmedLine.hasPrefix("# The Shift") {
                currentSection = "shift"
                continue
            } else if trimmedLine.hasPrefix("# The Anchor") {
                currentSection = "anchor"
                continue
            } else if trimmedLine.hasPrefix("# The Mechanism") {
                currentSection = "mechanism"
                continue
            } else if trimmedLine.hasPrefix("# The Lens") {
                currentSection = "lens"
                continue
            } else if trimmedLine.hasPrefix("# The Rabbit Hole") {
                currentSection = "rabbitHole"
                continue
            }
            
            // Legacy headers fallback
            if trimmedLine.hasPrefix("# Thesis") { currentSection = "thesis"; continue }
            if trimmedLine.hasPrefix("# Story") { currentSection = "story"; continue }
            if trimmedLine.hasPrefix("# Examples") { currentSection = "examples"; continue }
            if trimmedLine.hasPrefix("# Use it when") { currentSection = "useItWhen"; continue }
            if trimmedLine.hasPrefix("# How to apply") { currentSection = "howToApply"; continue }
            if trimmedLine.hasPrefix("# Edges & limits") { currentSection = "edgesAndLimits"; continue }
            if trimmedLine.hasPrefix("# One-line recall") { currentSection = "oneLineRecall"; continue }
            if trimmedLine.hasPrefix("# Further learning") { currentSection = "furtherLearning"; continue }
            
            switch currentSection {
            case "shift":
                parsed.shift += trimmedLine + " "
            case "anchor":
                if trimmedLine.lowercased().hasPrefix("source:") {
                    if trimmedLine.lowercased().contains("author metaphor") { parsed.anchorIsAuthorMetaphor = true }
                    continue
                }
                if trimmedLine.lowercased().hasPrefix("analogy:") {
                    let analogy = trimmedLine.replacingOccurrences(of: "Analogy:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                    parsed.anchor += analogy + " "
                } else {
                    parsed.anchor += trimmedLine + " "
                }
            case "mechanism":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine
                        .replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { parsed.mechanism.append(item) }
                }
            case "lens":
                if trimmedLine.lowercased().hasPrefix("when you see") {
                    parseLensLine(trimmedLine, isFeel: false)
                } else if trimmedLine.lowercased().hasPrefix("when you feel") {
                    parseLensLine(trimmedLine, isFeel: true)
                }
            case "rabbitHole":
                if trimmedLine.hasPrefix("-") {
                    let entry = trimmedLine.dropFirst().trimmingCharacters(in: .whitespaces)
                    if let colonIndex = entry.firstIndex(of: ":") {
                        let labelText = String(entry[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let queryText = String(entry[entry.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                        if !queryText.isEmpty {
                            parsed.rabbitHole.append(RabbitHoleItem(label: labelFrom(labelText), query: queryText))
                        }
                    }
                }
            case "thesis":
                parsed.thesis += trimmedLine + " "
            case "story":
                parsed.story += trimmedLine + " "
            case "examples":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine
                        .replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { parsed.examples.append(item) }
                } else {
                    parsed.examples.append(trimmedLine)
                }
            case "useItWhen":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { parsed.useItWhen.append(item) }
                }
            case "howToApply":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { parsed.howToApply.append(item) }
                }
            case "edgesAndLimits":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { parsed.edgesAndLimits.append(item) }
                }
            case "oneLineRecall":
                parsed.oneLineRecall += trimmedLine + " "
            case "furtherLearning":
                if trimmedLine.hasPrefix("-") {
                    let linkText = trimmedLine.replacingOccurrences(of: "- ", with: "")
                    if let colonIndex = linkText.firstIndex(of: ":") {
                        let title = String(linkText[..<colonIndex])
                            .trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "[", with: "")
                            .replacingOccurrences(of: "]", with: "")
                        var url = String(linkText[linkText.index(after: colonIndex)...])
                            .trimmingCharacters(in: .whitespaces)
                        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                            url = "https://" + url
                        }
                        parsed.furtherLearning.append(PrimerLink(title: title, url: url))
                    }
                }
            default:
                break
            }
        }
        
        // Post-processing trims and fallbacks
        parsed.shift = parsed.shift.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.anchor = parsed.anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.lensSee = parsed.lensSee.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.lensSeeWhy = parsed.lensSeeWhy.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.lensFeel = parsed.lensFeel.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.lensFeelWhy = parsed.lensFeelWhy.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.rabbitHole = parsed.rabbitHole.map { item in
            let cleaned = cleanQuery(item.query)
            return RabbitHoleItem(id: item.id, label: item.label, query: cleaned)
        }
        parsed.thesis = parsed.thesis.trimmingCharacters(in: .whitespaces)
        parsed.story = parsed.story.trimmingCharacters(in: .whitespaces)
        parsed.oneLineRecall = parsed.oneLineRecall.trimmingCharacters(in: .whitespaces)
        if parsed.oneLineRecall.isEmpty { parsed.oneLineRecall = parsed.shift }
        
        return parsed
    }

    // MARK: - On-demand Examples Generation

    func generateMoreExamples(for idea: Idea, avoiding existing: [String], count: Int = 2) async throws -> [String] {
        let system = "You generate specific, multi-sentence scenario examples for educational primers."
        let avoidList = existing.joined(separator: "\n- ")
        func prompt(_ need: Int, stricter: Bool = false) -> String {
            let strictBlock = stricter ? "\nThe last ones were too generic. Make them more specific with concrete nouns, numbers, and outcomes. Do not define the idea; show it in action.\n" : "\n"
            return """
            Goal: Provide \(need) new, vivid examples (2–3 sentences each, ≤320 characters) for the idea "\(idea.title)" from "\(idea.bookTitle)".

            Source description (only use this, no outside facts):
            \(idea.ideaDescription)

            Avoid duplicates of these examples:
            - \(avoidList)

            Write each example as a scenario using: Context → Tension → Application → Outcome.
            Include at least one exact term from the description; do not restate the idea.
            No meta language (don't say "this idea/the theorem").
            \(strictBlock)
            Output format:
            # Examples
            - <example 1>
            - <example 2>

            Rules: Each example ≤320 characters. Must be specific, concrete, and outcome-focused.
            """
        }

        func parseExamples(from response: String) -> [String] {
            var results: [String] = []
            let lines = response.components(separatedBy: .newlines)
            var inExamples = false
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("# Examples") { inExamples = true; continue }
                if inExamples {
                    if t.hasPrefix("-") || t.hasPrefix("•") {
                        let item = t.replacingOccurrences(of: "- ", with: "")
                            .replacingOccurrences(of: "• ", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !item.isEmpty { results.append(item) }
                    } else if t.hasPrefix("# ") { break }
                }
            }
            return results
        }

        func containsSignificantTerm(_ s: String, from text: String) -> Bool {
            let words = text.split{ !$0.isLetter }.map { String($0) }.filter { $0.count >= 5 }
            let lower = s.lowercased()
            for w in words {
                if lower.contains(w.lowercased()) { return true }
            }
            return false
        }

        func validate(_ items: [String]) -> [String] {
            items.filter { item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                let len = trimmed.count
                if len < 120 || len > 320 { return false }
                let lower = trimmed.lowercased()
                if lower.hasPrefix(idea.title.lowercased() + " is ") ||
                    lower.hasPrefix(idea.title.lowercased() + " means ") ||
                    lower.hasPrefix(idea.title.lowercased() + " states ") ||
                    lower.hasPrefix(idea.title.lowercased() + " says ") {
                    return false
                }
                let hasNumber = lower.range(of: "\\d", options: .regularExpression) != nil
                let hasTerm = containsSignificantTerm(lower, from: idea.ideaDescription)
                if !(hasNumber || hasTerm) { return false }
                return true
            }
        }

        // First attempt
        let response1 = try await openAIService.chat(
            systemPrompt: system,
            userPrompt: prompt(count, stricter: false),
            model: "gpt-4.1-mini",
            temperature: 0.7,
            maxTokens: 800
        )
        var collected = validate(parseExamples(from: response1))

        // Retry once if needed
        if collected.count < count {
            let remaining = count - collected.count
            let response2 = try await openAIService.chat(
                systemPrompt: system,
                userPrompt: prompt(remaining, stricter: true),
                model: "gpt-4.1-mini",
                temperature: 0.6,
                maxTokens: 700
            )
            let second = validate(parseExamples(from: response2))
            collected.append(contentsOf: second)
        }

        // De-duplicate against existing and within new ones
        var unique: [String] = []
        let existingSet = Set(existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        for ex in collected {
            let t = ex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !existingSet.contains(t) && !unique.contains(t) {
                unique.append(t)
            }
            if unique.count == count { break }
        }
        return unique
    }

    func appendExamples(to primer: Primer, for idea: Idea, count: Int = 2) async throws -> Primer {
        let current = primer.examples
        let newOnes = try await generateMoreExamples(for: idea, avoiding: current, count: count)
        if !newOnes.isEmpty {
            primer.examples = current + newOnes
            try modelContext.save()
        }
        return primer
    }
} 
