import Foundation

struct AttentionConfig {
    // External distraction: app switched away duration threshold
    var awayThresholdSeconds: TimeInterval = 10
    // Internal distraction: no input inside app while testing
    var inactivityThresholdSeconds: TimeInterval = 60
    // Pause -> percent mapping
    var scoreMap: [Int: Int] = [
        0: 100,
        1: 80,
        2: 50
        // 3+ -> 0
    ]

    func percent(for pauses: Int) -> Int {
        if pauses <= 0 { return 100 }
        if let v = scoreMap[pauses] { return v }
        return pauses >= 3 ? 0 : 0
    }
}
