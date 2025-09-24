import Foundation

// MARK: - Google Books API Models
struct GoogleBooksResponse: Codable {
    let items: [GoogleBookItem]?
    let totalItems: Int
}

struct GoogleBookItem: Codable {
    let id: String
    let volumeInfo: VolumeInfo
}

struct VolumeInfo: Codable {
    let title: String
    let subtitle: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let language: String?
    let categories: [String]?
    let averageRating: Double?
    let ratingsCount: Int?
    let imageLinks: ImageLinks?
    let previewLink: String?
    let infoLink: String?
    let canonicalVolumeLink: String?
}

struct ImageLinks: Codable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
    let large: String?
    let extraLarge: String?
}

// MARK: - Book Metadata Model (for use in app)
struct BookMetadata {
    let googleBooksId: String
    let title: String
    let subtitle: String?
    let authors: [String]
    let publisher: String?
    let language: String?
    let categories: [String]
    let thumbnailUrl: String?
    let coverImageUrl: String?  // large or extraLarge
    let averageRating: Double?
    let ratingsCount: Int?
    let previewLink: String?
    let infoLink: String?
}

// MARK: - Google Books Service
class GoogleBooksService {
    static let shared = GoogleBooksService()
    
    private let apiKey = Secrets.googleBooksAPIKey
    private let baseURL = "https://www.googleapis.com/books/v1/volumes"
    private let session = URLSession.shared
    
    private init() {
        // Test API key on init
        Task {
            await testAPIKey()
        }
    }
    
    private func testAPIKey() async {
        print("DEBUG GoogleBooks: Testing API key...")
        let testURL = URL(string: "\(baseURL)?q=harry+potter&key=\(apiKey)&maxResults=1")!
        
        do {
            let (_, response) = try await session.data(from: testURL)
            if let httpResponse = response as? HTTPURLResponse {
                print("DEBUG GoogleBooks TEST: API Key test status: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 200 {
                    print("DEBUG GoogleBooks TEST: ✅ API Key is working!")
                } else {
                    print("DEBUG GoogleBooks TEST: ❌ API Key test failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("DEBUG GoogleBooks TEST: ❌ API Key test error: \(error)")
        }
    }
    
    /// Search for a book by title and author
    /// Simple, robust flow: try intitle+inauthor, then fallback to intitle only, then raw title.
    func searchBook(title: String, author: String?) async throws -> BookMetadata? {
        print("DEBUG GoogleBooks: Searching for title: '\(title)', author: '\(author ?? "nil")'")
        
        // Build search query
        var query = "intitle:\"\(title)\""
        if let author = author, !author.isEmpty {
            query += "+inauthor:\"\(author)\""
        }
        // Exclude common summary/guide terms to reduce wrong covers
        query += " -summary -guide -analysis -workbook -study"
        
        print("DEBUG GoogleBooks: Query: \(query)")
        
        // Attempt 1: intitle + inauthor (if provided) with negative terms
        if let best = try await performRequestAndSelectBest(query: query, title: title, author: author) {
            return best
        }

        // Attempt 2: intitle only with negative terms (in case author was wrong)
        let queryTitleOnly = "intitle:\"\(title)\" -summary -guide -analysis -workbook -study"
        print("DEBUG GoogleBooks: Fallback query (title only): \(queryTitleOnly)")
        if let best = try await performRequestAndSelectBest(query: queryTitleOnly, title: title, author: nil) {
            return best
        }

        // Attempt 3: raw title, no negative terms (broadest)
        let queryBroad = "\(title)"
        print("DEBUG GoogleBooks: Fallback query (broad): \(queryBroad)")
        return try await performRequestAndSelectBest(query: queryBroad, title: title, author: nil)
    }

    private func performRequestAndSelectBest(query: String, title: String, author: String?) async throws -> BookMetadata? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "orderBy", value: "relevance")
        ]

        guard let url = components.url else {
            print("DEBUG GoogleBooks: Invalid URL")
            throw GoogleBooksError.invalidURL
        }
        print("DEBUG GoogleBooks: Request URL: \(url.absoluteString.replacingOccurrences(of: apiKey, with: "***"))")
        print("DEBUG GoogleBooks: API Key starts with: \(String(apiKey.prefix(10)))")

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            print("DEBUG GoogleBooks: Invalid response type")
            throw GoogleBooksError.invalidResponse
        }
        print("DEBUG GoogleBooks: Response status code: \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200: break
        case 429: throw GoogleBooksError.rateLimitExceeded
        case 403: throw GoogleBooksError.invalidAPIKey
        default: throw GoogleBooksError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            let booksResponse = try decoder.decode(GoogleBooksResponse.self, from: data)
            let count = booksResponse.items?.count ?? 0
            print("DEBUG GoogleBooks: Found \(count) results")
            guard let items = booksResponse.items, !items.isEmpty else { return nil }
            let candidates = items.map { mapToBookMetadata($0) }
            let best = selectBestCandidate(from: candidates, forTitle: title, author: author)
            if let best = best {
                print("DEBUG GoogleBooks: Selected best candidate: '\(best.title)' by \(best.authors.first ?? "unknown") | Cover: \(best.coverImageUrl ?? "none")")
            }
            return best
        } catch {
            print("DEBUG GoogleBooks: Failed to decode response: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("DEBUG GoogleBooks: Response data: \(responseString.prefix(500))")
            }
            throw error
        }
    }

    // MARK: - Candidate selection helpers

    private func baseTitle(_ text: String) -> String {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Split on common subtitle separators
        let separators: [Character] = [":", "—", "-"]
        if let idx = lowered.firstIndex(where: { separators.contains($0) }) {
            return stripLeadingArticles(String(lowered[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stripLeadingArticles(lowered)
    }

    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let cleaned = String(String.UnicodeScalarView(allowed)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripLeadingArticles(_ text: String) -> String {
        let articles = ["the ", "a ", "an "]
        for a in articles {
            if text.hasPrefix(a) { return String(text.dropFirst(a.count)) }
        }
        return text
    }

    private func isSummaryLike(title: String?, subtitle: String?, publisher: String?, categories: [String]) -> Bool {
        let hay = [title, subtitle, publisher].compactMap { $0?.lowercased() }.joined(separator: " ")
        let keywords = ["summary", "study guide", "workbook", "analysis", "key takeaways", "instaread", "readtrepreneur", "bookrags", "blinkist", "shortcut", "gwhiz"]
        if keywords.contains(where: { hay.contains($0) }) { return true }
        // Category-based exclusions for common wrong picks
        let lowerCats = categories.map { $0.lowercased() }
        let badCats = ["comics & graphic novels", "comic", "humor", "juvenile fiction", "juvenile nonfiction", "study aids"]
        if lowerCats.contains(where: { cat in badCats.contains(where: { cat.contains($0) }) }) { return true }
        return false
    }

    private func score(_ candidate: BookMetadata, inputTitle: String, inputAuthor: String?) -> Double {
        let inBase = baseTitle(inputTitle)
        let cBase = baseTitle(candidate.title)
        let inNorm = normalize(inBase)
        let cNorm = normalize(cBase)
        var score: Double = 0

        if cNorm == inNorm { score += 0.7 }
        else if cNorm.hasPrefix(inNorm) || inNorm.hasPrefix(cNorm) { score += 0.4 }

        if authorMatches(candidate, inputAuthor: inputAuthor) { score += 0.35 }

        if let ratings = candidate.ratingsCount, ratings > 50 { score += 0.08 }
        if candidate.coverImageUrl != nil || candidate.thumbnailUrl != nil { score += 0.06 }

        return score
    }

    private func selectBestCandidate(from candidates: [BookMetadata], forTitle title: String, author: String?) -> BookMetadata? {
        // Filter out obvious summaries/guides and excluded categories
        let filtered = candidates.filter { !isSummaryLike(title: $0.title + (" \($0.subtitle ?? "")"), subtitle: $0.subtitle, publisher: $0.publisher, categories: $0.categories) }
        let pool = filtered.isEmpty ? candidates : filtered

        // Require author match if provided to prevent unrelated covers
        if let _ = author {
            let authorPool = pool.filter { authorMatches($0, inputAuthor: author) }
            if authorPool.isEmpty { return nil }
            return pickByTitleSimilarity(from: authorPool, inputTitle: title)
        }

        // No author provided: pick by strong title similarity
        return pickByTitleSimilarity(from: pool, inputTitle: title)
    }

    private func pickByTitleSimilarity(from list: [BookMetadata], inputTitle: String) -> BookMetadata? {
        let inputTokens = titleTokens(in: inputTitle)
        let inputBase = normalize(baseTitle(inputTitle))

        // 1) Exact base-title match
        let exact = list.filter { normalize(baseTitle($0.title)) == inputBase }
        if let chosen = pickWithImageAndRatings(from: exact) { return chosen }

        // 2) Phrase match on best segment
        let normPhrase = normalize(inputBase)
        let phraseMatches = list.filter { normalize(baseTitle(bestMatchingSegmentKey(for: $0.title, inputTokens: inputTokens))).contains(normPhrase) }
        if let chosen = pickWithImageAndRatings(from: phraseMatches) { return chosen }

        // 3) Token overlap threshold (strict)
        var best: (candidate: BookMetadata, overlap: Double, hasImage: Int, ratings: Int)? = nil
        for c in list {
            let seg = bestMatchingSegmentKey(for: c.title, inputTokens: inputTokens)
            let candTokens = titleTokens(in: seg)
            let overlapCount = inputTokens.intersection(candTokens).count
            let overlap = inputTokens.isEmpty ? 0.0 : Double(overlapCount) / Double(inputTokens.count)
            let hasImage = (c.coverImageUrl != nil || c.thumbnailUrl != nil) ? 1 : 0
            let ratings = c.ratingsCount ?? 0
            if best == nil || overlap > best!.overlap || (overlap == best!.overlap && hasImage > best!.hasImage) || (overlap == best!.overlap && hasImage == best!.hasImage && ratings > best!.ratings) {
                best = (c, overlap, hasImage, ratings)
            }
        }
        if let best = best, best.overlap >= 0.75 {
            return best.candidate
        }
        return nil
    }

    private func bestMatchingSegmentKey(for title: String, inputTokens: Set<String>) -> String {
        // Split on subtitle separators and pick segment with highest token overlap with input
        let lowered = title.lowercased()
        let parts = lowered.split(whereSeparator: { $0 == ":" || $0 == "—" || $0 == "-" }).map { String($0) }
        if parts.isEmpty { return title }
        var best: (String, Int) = (parts[0], 0)
        for p in parts {
            let tokens = titleTokens(in: p)
            let common = tokens.intersection(inputTokens).count
            if common > best.1 { best = (p, common) }
        }
        return best.0
    }

    private func pickWithImageAndRatings(from list: [BookMetadata]) -> BookMetadata? {
        guard !list.isEmpty else { return nil }
        let chosen = list.max {
            let lhs = (($0.coverImageUrl != nil || $0.thumbnailUrl != nil) ? 1 : 0, $0.ratingsCount ?? 0)
            let rhs = (($1.coverImageUrl != nil || $1.thumbnailUrl != nil) ? 1 : 0, $1.ratingsCount ?? 0)
            return lhs < rhs
        }
        return chosen
    }

    private func authorMatches(_ candidate: BookMetadata, inputAuthor: String?) -> Bool {
        guard let inputAuthor = inputAuthor?.lowercased(), !inputAuthor.isEmpty else { return false }
        let lastName = inputAuthor.split(separator: " ").last.map(String.init)?.lowercased() ?? inputAuthor
        let authorsJoined = candidate.authors.joined(separator: " ").lowercased()
        return authorsJoined.contains(lastName)
    }

    private func titleTokens(in title: String) -> Set<String> {
        let stop: Set<String> = ["a","an","the","of","and","to","in","on","for","by","with","from","at","as"]
        let norm = normalize(baseTitle(title))
        let tokens = norm.split(separator: " ").map { String($0) }.filter { !$0.isEmpty && !stop.contains($0) }
        return Set(tokens)
    }
    
    /// Map Google Books API response to our BookMetadata model
    private func mapToBookMetadata(_ item: GoogleBookItem) -> BookMetadata {
        let volumeInfo = item.volumeInfo
        
        // Choose best available image URLs and convert HTTP to HTTPS
        let thumbnailUrl = (volumeInfo.imageLinks?.thumbnail ?? volumeInfo.imageLinks?.smallThumbnail)?
            .replacingOccurrences(of: "http://", with: "https://")
        let coverImageUrl = (volumeInfo.imageLinks?.extraLarge ?? 
                           volumeInfo.imageLinks?.large ?? 
                           volumeInfo.imageLinks?.medium)?
            .replacingOccurrences(of: "http://", with: "https://")
        
        print("DEBUG GoogleBooks: Image URLs - Thumbnail: \(thumbnailUrl ?? "none"), Cover: \(coverImageUrl ?? "none")")
        
        return BookMetadata(
            googleBooksId: item.id,
            title: volumeInfo.title,
            subtitle: volumeInfo.subtitle,
            authors: volumeInfo.authors ?? [],
            publisher: volumeInfo.publisher,
            language: volumeInfo.language,
            categories: volumeInfo.categories ?? [],
            thumbnailUrl: thumbnailUrl,
            coverImageUrl: coverImageUrl,
            averageRating: volumeInfo.averageRating,
            ratingsCount: volumeInfo.ratingsCount,
            previewLink: volumeInfo.previewLink,
            infoLink: volumeInfo.infoLink
        )
    }
}

// MARK: - Errors
enum GoogleBooksError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case rateLimitExceeded
    case httpError(statusCode: Int)
    case noResults
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for Google Books API"
        case .invalidResponse:
            return "Invalid response from Google Books API"
        case .invalidAPIKey:
            return "Invalid or missing Google Books API key"
        case .rateLimitExceeded:
            return "Google Books API rate limit exceeded. Please try again later."
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .noResults:
            return "No books found matching your search"
        }
    }
}
