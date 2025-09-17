import Foundation

enum DebugFlags {
    // Toggle to expose developer/test-only controls in the UI.
    static let enableDevControls: Bool = true

    // Feature flag to enable batched initial question generation (single API call for 8 items)
    static let useBatchedInitialGeneration: Bool = true
}
