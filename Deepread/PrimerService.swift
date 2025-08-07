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
        
        // Create and save the primer
        let primer = Primer(
            ideaId: idea.id,
            overview: parsedPrimer.overview,
            keyNuances: parsedPrimer.keyNuances,
            digDeeperLinks: parsedPrimer.digDeeperLinks
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
        Your task is to generate a "Primer" for the idea "\(idea.title)" from the book "\(idea.bookTitle)".

        Use ONLY the following description as your source material—do not add external knowledge, interpretations, or details not explicitly in this description: \(idea.ideaDescription).

        The Primer should be a short, efficient refresher that stays true to the author's intended voice, tone, and content as reflected in the description.

        Focus on brevity to allow users to grasp the idea in the shortest time possible, covering key aspects without unnecessary depth.

        Structure the output exactly as follows:
        1. **Overview**: A 150-250 word summary explaining the idea, its key components, significance, impacts, or value—keep it concise and skimmable.
        2. **Key Nuances**: 4-6 bullet points covering subtleties, examples, or limitations from the description—make each bullet short and direct.
        3. **Dig Deeper Hyperlinks**: Suggest 3-5 relevant hyperlinks for further reading.

        These should be logical recommendations based solely on the book title and idea (e.g., official book pages, author sites, or public-domain excerpts).

        Format as: - [Link Title]: [URL] (use placeholders like amazon.com/[book-title] if exact URLs aren't known).

        Keep the tone neutral, factual, and true to the description's style (e.g., if it's analytical, be precise; if narrative, be straightforward).

        Ensure the Primer is quick to read (under 5 minutes) and feels like a search result—informative and to-the-point.
        """
    }
    
    private func parsePrimerResponse(_ response: String) throws -> (overview: String, keyNuances: [String], digDeeperLinks: [PrimerLink]) {
        // Simple parsing logic - you might want to make this more robust
        let lines = response.components(separatedBy: .newlines)
        
        var overview = ""
        var keyNuances: [String] = []
        var digDeeperLinks: [PrimerLink] = []
        
        var currentSection = ""
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.contains("**Overview**") {
                currentSection = "overview"
                continue
            } else if trimmedLine.contains("**Key Nuances**") {
                currentSection = "nuances"
                continue
            } else if trimmedLine.contains("**Dig Deeper Hyperlinks**") {
                currentSection = "links"
                continue
            }
            
            switch currentSection {
            case "overview":
                if !trimmedLine.isEmpty {
                    overview += trimmedLine + " "
                }
            case "nuances":
                if trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("•") {
                    let nuance = trimmedLine.replacingOccurrences(of: "- ", with: "")
                        .replacingOccurrences(of: "• ", with: "")
                    if !nuance.isEmpty {
                        keyNuances.append(nuance)
                    }
                }
            case "links":
                if trimmedLine.hasPrefix("-") {
                    let linkText = trimmedLine.replacingOccurrences(of: "- ", with: "")
                    if let colonIndex = linkText.firstIndex(of: ":") {
                        let title = String(linkText[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        var url = String(linkText[linkText.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                        
                        // Ensure URL has proper scheme
                        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                            url = "https://" + url
                        }
                        
                        digDeeperLinks.append(PrimerLink(title: title, url: url))
                    }
                }
            default:
                break
            }
        }
        
        return (overview.trimmingCharacters(in: .whitespaces), keyNuances, digDeeperLinks)
    }
} 