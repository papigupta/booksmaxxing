import Foundation
import SwiftData

final class CloudSyncRefresh {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func warmFetches() {
        Task { @MainActor in
            _ = try? modelContext.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.createdAt)]))
            var ideas = FetchDescriptor<Idea>()
            ideas.fetchLimit = 50
            _ = try? modelContext.fetch(ideas)
            var progress = FetchDescriptor<Progress>()
            progress.fetchLimit = 50
            _ = try? modelContext.fetch(progress)
            var primers = FetchDescriptor<Primer>()
            primers.fetchLimit = 20
            _ = try? modelContext.fetch(primers)
            var tests = FetchDescriptor<Test>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            tests.fetchLimit = 10
            _ = try? modelContext.fetch(tests)
        }
    }
}

import Foundation

enum SharedUtils {
    /// Extracts the outermost JSON object substring from a response string.
    /// Falls back to returning the full response if braces are not found.
    static func extractJSONObjectString(_ response: String) -> String {
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        return response
    }
}

