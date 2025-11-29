import Foundation

struct StarterBookIdeaSeed: Decodable {
    let id: String
    let title: String
    let description: String
    let importance: StarterIdeaImportance
    let depthTarget: Int

    func makeIdea(for bookTitle: String) -> Idea {
        Idea(
            id: id,
            title: title,
            description: description,
            bookTitle: bookTitle,
            depthTarget: depthTarget,
            importance: importance.importanceLevel
        )
    }
}

enum StarterIdeaImportance: String, Decodable {
    case foundation
    case buildingBlock
    case enhancement

    var importanceLevel: ImportanceLevel {
        switch self {
        case .foundation: return .foundation
        case .buildingBlock: return .buildingBlock
        case .enhancement: return .enhancement
        }
    }
}

struct StarterBookSeed: Decodable {
    let starterId: String
    let title: String
    let author: String
    let description: String
    let coverImageUrl: String
    let thumbnailUrl: String
    let ideas: [StarterBookIdeaSeed]

    func metadata() -> BookMetadata {
        BookMetadata(
            googleBooksId: starterId,
            title: title,
            subtitle: nil,
            description: description,
            authors: [author].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            publisher: nil,
            language: nil,
            categories: [],
            publishedDate: nil,
            thumbnailUrl: thumbnailUrl.isEmpty ? nil : thumbnailUrl,
            coverImageUrl: coverImageUrl.isEmpty ? nil : coverImageUrl,
            averageRating: nil,
            ratingsCount: nil,
            previewLink: nil,
            infoLink: nil
        )
    }
}

enum StarterLibraryError: Error {
    case resourceMissing
    case decodingFailed(Error)
}

final class StarterLibrary {
    static let shared = StarterLibrary()
    static let currentVersion = 1

    private var cachedSeeds: [StarterBookSeed]?

    private init() {}

    func books() throws -> [StarterBookSeed] {
        if let cachedSeeds {
            return cachedSeeds
        }
        guard let url = Bundle.main.url(forResource: "StarterBooks", withExtension: "json") else {
            assertionFailure("StarterBooks.json is missing from the app bundle.")
            throw StarterLibraryError.resourceMissing
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let seeds = try decoder.decode([StarterBookSeed].self, from: data)
            cachedSeeds = seeds
            return seeds
        } catch {
            assertionFailure("Failed to decode StarterBooks.json: \(error)")
            throw StarterLibraryError.decodingFailed(error)
        }
    }
}
