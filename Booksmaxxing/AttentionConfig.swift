import Foundation

struct AttentionConfig {
    var awayThresholdSeconds: TimeInterval = 15
    var inactivityThresholdSeconds: TimeInterval = 45
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

