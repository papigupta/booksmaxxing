import Foundation
import SwiftData

class PrimerService: ObservableObject {
    private let openAIService: OpenAIService
    private var modelContext: ModelContext
    
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
        let prompt = createPrimerPrompt(for: idea)
        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                Message(role: "system", content: "You are an expert summarizer specializing in distilling core ideas from books into concise primers, like those in book summary apps."),
                Message(role: "user", content: prompt)
            ],
            max_tokens: 2000,
            temperature: 0.7
        )
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIServiceError.invalidResponse
        }
        
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        let primerContent = chatResponse.choices.first?.message.content ?? ""
        
        // Parse the response into structured data
        let parsedPrimer = try parsePrimerResponse(primerContent)
        
        // Create and save the primer with new structure
        let primer = Primer(
            ideaId: idea.id,
            thesis: parsedPrimer.thesis,
            core: parsedPrimer.core,
            story: parsedPrimer.story,
            useItWhen: parsedPrimer.useItWhen,
            howToApply: parsedPrimer.howToApply,
            edgesAndLimits: parsedPrimer.edgesAndLimits,
            oneLineRecall: parsedPrimer.oneLineRecall,
            furtherLearning: parsedPrimer.furtherLearning
        )
        
        primer.idea = idea
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

        # Core (110–150 words)
        Explain what it is, how it works, and why it matters — strictly in the author's voice. Each sentence must add new information.
        
        # Story (80–120 words)
        Share a compelling narrative or example that illustrates this idea in action. Use concrete details and make it memorable.

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

        Rules: No repetition across sections. No hedging. Don't invent examples; if the description includes one, compress it briefly in Story section. Total length ≤ 320 words.
        """
    }
    
    private func parsePrimerResponse(_ response: String) throws -> (thesis: String, core: String, story: String, useItWhen: [String], howToApply: [String], edgesAndLimits: [String], oneLineRecall: String, furtherLearning: [PrimerLink]) {
        let lines = response.components(separatedBy: .newlines)
        
        var thesis = ""
        var core = ""
        var story = ""
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
            } else if trimmedLine.hasPrefix("# Core") {
                currentSection = "core"
                continue
            } else if trimmedLine.hasPrefix("# Story") {
                currentSection = "story"
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
            case "core":
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    core += trimmedLine + " "
                }
            case "story":
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    story += trimmedLine + " "
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
            core: core.trimmingCharacters(in: .whitespaces),
            story: story.trimmingCharacters(in: .whitespaces),
            useItWhen: useItWhen,
            howToApply: howToApply,
            edgesAndLimits: edgesAndLimits,
            oneLineRecall: oneLineRecall.trimmingCharacters(in: .whitespaces),
            furtherLearning: furtherLearning
        )
    }
} 