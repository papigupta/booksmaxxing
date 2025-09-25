import Foundation

enum DebugFlags {
    // Toggle to expose developer/test-only controls in the UI.
    static let enableDevControls: Bool = true

    // Toggle to enable the in-app Theme Lab for rapid UI experimentation.
    static let enableThemeLab: Bool = true

    // Feature flag to enable batched initial question generation (single API call for 8 items)
    static let useBatchedInitialGeneration: Bool = true

    // Feature flag to enable per-difficulty batched initial generation (3 API calls: Easy, Medium, Hard)
    // This supersedes the single-call batching when enabled.
    static let usePerDifficultyBatchedInitialGeneration: Bool = true

    // Enable making multiple concurrent HTTP connections to OpenAI for parallel batch calls.
    // When enabled, OpenAIService will allow up to 3 connections per host; otherwise it remains 1.
    static let enableParallelOpenAI: Bool = true
}
