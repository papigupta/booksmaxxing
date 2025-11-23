import Testing
@testable import Booksmaxxing
import Foundation

struct OpenAIServiceRetryTests {
    private struct StubNetwork: NetworkStatusProviding {
        let isConnected: Bool
    }

    private enum RetryError: Error { case fail }

    @Test
    func retriesUntilSuccess() async throws {
        var attempts = 0
        let service = OpenAIService(
            apiKey: "test",
            session: URLSession(configuration: .ephemeral),
            networkMonitor: StubNetwork(isConnected: true),
            sleepHandler: { _ in } // avoid real delay during tests
        )

        let value: String = try await service.withRetry(maxAttempts: 3) {
            attempts += 1
            if attempts < 3 { throw RetryError.fail }
            return "ok"
        }

        #expect(attempts == 3)
        #expect(value == "ok")
    }
}
