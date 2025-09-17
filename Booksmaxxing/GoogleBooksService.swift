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
    func searchBook(title: String, author: String?) async throws -> BookMetadata? {
        print("DEBUG GoogleBooks: Searching for title: '\(title)', author: '\(author ?? "nil")'")
        
        // Build search query
        var query = "intitle:\"\(title)\""
        if let author = author, !author.isEmpty {
            query += "+inauthor:\"\(author)\""
        }
        
        print("DEBUG GoogleBooks: Query: \(query)")
        
        // Build URL with parameters
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "maxResults", value: "1")  // We only need the best match
        ]
        
        guard let url = components.url else {
            print("DEBUG GoogleBooks: Invalid URL")
            throw GoogleBooksError.invalidURL
        }
        
        print("DEBUG GoogleBooks: Request URL: \(url.absoluteString.replacingOccurrences(of: apiKey, with: "***"))")
        print("DEBUG GoogleBooks: API Key starts with: \(String(apiKey.prefix(10)))")
        
        // Make API request
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("DEBUG GoogleBooks: Invalid response type")
            throw GoogleBooksError.invalidResponse
        }
        
        print("DEBUG GoogleBooks: Response status code: \(httpResponse.statusCode)")
        
        switch httpResponse.statusCode {
        case 200:
            print("DEBUG GoogleBooks: Success")
            break
        case 429:
            print("DEBUG GoogleBooks: Rate limit exceeded")
            throw GoogleBooksError.rateLimitExceeded
        case 403:
            print("DEBUG GoogleBooks: Invalid API key or forbidden")
            throw GoogleBooksError.invalidAPIKey
        default:
            print("DEBUG GoogleBooks: HTTP error \(httpResponse.statusCode)")
            throw GoogleBooksError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Parse response
        let decoder = JSONDecoder()
        do {
            let booksResponse = try decoder.decode(GoogleBooksResponse.self, from: data)
            print("DEBUG GoogleBooks: Found \(booksResponse.items?.count ?? 0) results")
            
            // Get first result if available
            guard let firstItem = booksResponse.items?.first else {
                print("DEBUG GoogleBooks: No results found")
                return nil  // No results found
            }
            
            let metadata = mapToBookMetadata(firstItem)
            print("DEBUG GoogleBooks: Successfully mapped metadata - Cover URL: \(metadata.coverImageUrl ?? "none")")
            return metadata
        } catch {
            print("DEBUG GoogleBooks: Failed to decode response: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("DEBUG GoogleBooks: Response data: \(responseString.prefix(500))")
            }
            throw error
        }
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