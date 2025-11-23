import Testing
@testable import Booksmaxxing
import SwiftData

@MainActor
struct TestGenerationServiceTests {
    private func makeService() throws -> TestGenerationService {
        let container = try ModelContainer(for: Book.self, Idea.self, Test.self, Question.self)
        let context = ModelContext(container)
        let openAI = OpenAIService(apiKey: "test", session: .shared, networkMonitor: NetworkMonitor(), sleepHandler: { _ in })
        return TestGenerationService(openAI: openAI, modelContext: context)
    }

    @Test
    func randomizeOptionsPreservesCorrectAnswers() async throws {
        let service = try makeService()
        let options = ["Option A", "Option B", "Option C", "Option D"]
        let correct = [1, 3]

        let result = service.randomizeOptions(options, correctIndices: correct)

        #expect(Set(result.options) == Set(options))
        let originalCorrect = Set(correct.map { options[$0] })
        let mappedCorrect = Set(result.correctIndices.map { result.options[$0] })
        #expect(originalCorrect == mappedCorrect)
    }
}
