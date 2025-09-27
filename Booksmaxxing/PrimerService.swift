import Foundation
import SwiftData
import OSLog

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
        let system = "You are an expert summarizer specializing in distilling core ideas from books into concise primers, like those in book summary apps."

        let primerContent = try await openAIService.chat(
            systemPrompt: system,
            userPrompt: userPrompt,
            model: "gpt-4.1",
            temperature: 0.7,
            maxTokens: 2000
        )
        
        // Parse the response into structured data
        let parsedPrimer = try parsePrimerResponse(primerContent)
        
        // Create and save the primer with new structure
        let primer = Primer(
            ideaId: idea.id,
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
        GOAL: Teach "\(idea.title)" (from "\(idea.bookTitle)") in one page, ready to use now.

        SOURCE: Use only this description; add no outside facts:
        \(idea.ideaDescription)

        Voice: Mirror the author's diction, cadence, and stance in the description. Reuse key terms verbatim. Vary sentence length. No filler. No meta (don't say "in this primer/section").

        Output format — use these exact headings:

        # Thesis (≤22 words)
        A single, sharp claim that captures the idea's essence.
        
        # Story (80–120 words)
        Share a compelling narrative or example that illustrates this idea in action. Use concrete details and make it memorable.

        # Examples (1 example, 2–3 sentences, ≤320 characters)
        - Write one vivid, concrete scenario showing the idea in action.
        - Use the shape: Context → Tension → Application → Outcome.
        - Include at least one exact term from the description; avoid redefining the idea.
        - No meta language (don't say "this idea/the theorem").

        # Use it when… (3 bullets, ≤10 words each)
        Concrete cues/conditions that signal the idea applies.

        # How to apply (3 bullets, ≤12 words each, verb-first)
        Actionable steps or checks drawn only from the description.

        # Edges & limits (2–3 bullets, ≤12 words)
        Boundaries, exceptions, or trade-offs stated or implied in the description.

        # One-line recall (≤14 words)
        A memorable line in the author's tone.

        # Further learning (3–4 links)
        - [Official/book page]: https://amazon.com/<book-slug-or-isbn>
        - [In-depth article]: https://<reputable-site>/<book-or-idea-slug>
        - [Talk/lecture video]: https://youtube.com/results?search_query=<author+idea+book>
        - [Review/critique]: https://<quality-blog>/<book-or-idea-review>

        Rules: No repetition across sections. No hedging. The example must be ≤320 characters, concrete, and non-definitional. Total length ≤ 240 words.
        """
    }
    
    private func parsePrimerResponse(_ response: String) throws -> (
        thesis: String,
        story: String,
        examples: [String],
        useItWhen: [String],
        howToApply: [String],
        edgesAndLimits: [String],
        oneLineRecall: String,
        furtherLearning: [PrimerLink]
    ) {
        let lines = response.components(separatedBy: .newlines)
        
        var thesis = ""
        var story = ""
        var examples: [String] = []
        var useItWhen: [String] = []
        var howToApply: [String] = []
        var edgesAndLimits: [String] = []
        var oneLineRecall = ""
        var furtherLearning: [PrimerLink] = []
        
        var currentSection = ""
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check for section headers
            if trimmedLine.hasPrefix("# Thesis") {
                currentSection = "thesis"
                continue
            } else if trimmedLine.hasPrefix("# Story") {
                currentSection = "story"
                continue
            } else if trimmedLine.hasPrefix("# Examples") {
                currentSection = "examples"
                continue
            } else if trimmedLine.hasPrefix("# Use it when") {
                currentSection = "useItWhen"
                continue
            } else if trimmedLine.hasPrefix("# How to apply") {
                currentSection = "howToApply"
                continue
            } else if trimmedLine.hasPrefix("# Edges & limits") {
                currentSection = "edgesAndLimits"
                continue
            } else if trimmedLine.hasPrefix("# One-line recall") {
                currentSection = "oneLineRecall"
                continue
            } else if trimmedLine.hasPrefix("# Further learning") {
                currentSection = "furtherLearning"
                continue
            }
            
            // Process content based on current section
            switch currentSection {
            case "thesis":
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    thesis += trimmedLine + " "
                }
            case "story":
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    story += trimmedLine + " "
                }
            case "examples":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine
                        .replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty {
                        examples.append(item)
                    }
                } else if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    // Fallback if model returns a single line without bullet
                    examples.append(trimmedLine)
                }
            case "useItWhen":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                    if !item.isEmpty {
                        useItWhen.append(item)
                    }
                }
            case "howToApply":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                    if !item.isEmpty {
                        howToApply.append(item)
                    }
                }
            case "edgesAndLimits":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let item = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                    if !item.isEmpty {
                        edgesAndLimits.append(item)
                    }
                }
            case "oneLineRecall":
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    oneLineRecall += trimmedLine + " "
                }
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
                        
                        // Ensure URL has proper scheme
                        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                            url = "https://" + url
                        }
                        
                        furtherLearning.append(PrimerLink(title: title, url: url))
                    }
                }
            default:
                break
            }
        }
        
        return (
            thesis: thesis.trimmingCharacters(in: .whitespaces),
            story: story.trimmingCharacters(in: .whitespaces),
            examples: examples,
            useItWhen: useItWhen,
            howToApply: howToApply,
            edgesAndLimits: edgesAndLimits,
            oneLineRecall: oneLineRecall.trimmingCharacters(in: .whitespaces),
            furtherLearning: furtherLearning
        )
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
