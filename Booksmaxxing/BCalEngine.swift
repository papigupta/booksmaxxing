import Foundation

// MARK: - Brain Calories (BCal) Engine

struct BCalConfig {
    // Global scaling
    var base: Double = 10.0
    var lessonScale: Double = 0.9
    var lessonClamp: ClosedRange<Int> = 60...500

    // Type weights
    var typeWeights: [QuestionType: Double] = [
        .mcq: 1.0,
        .msq: 1.0, // MSQ currently unused; kept for forward-compat
        .openEnded: 2.5
    ]

    // State weights (highest wins)
    struct StateW {
        var fresh: Double = 1.0
        var review: Double = 1.1
        var spfu: Double = 1.1
        var curveball: Double = 1.5
    }
    var state = StateW()

    // Difficulty weights
    var depthWeights: [QuestionDifficulty: Double] = [
        .easy: 1.0,
        .medium: 1.5,
        .hard: 2.0
    ]

    // Struggle parameters
    struct StruggleParams {
        var base: Double = 0.5
        var latencyDivisor: Double = 45.0
        var primerUsed: Double = 0.6
        var optionChange: Double = 0.15
    }
    var struggle = StruggleParams()

    // Default latencies when not captured
    var defaultLatencyByType: [QuestionType: Double] = [
        .mcq: 15.0,
        .msq: 15.0,
        .openEnded: 25.0
    ]
}

struct BCalQuestionSignals {
    var latencySeconds: Double
    var primerUsed: Bool
    var optionChanges: Int
}

struct BCalQuestionContext {
    var type: QuestionType
    var difficulty: QuestionDifficulty
    // State flags
    var isCurveball: Bool
    var isSpacedFollowUp: Bool
    var isReview: Bool
}

final class BCalEngine {
    static let shared = BCalEngine()
    var config = BCalConfig()

    func bcalForQuestion(context: BCalQuestionContext, signals: BCalQuestionSignals) -> Double {
        let cfg = config
        let typeW = cfg.typeWeights[context.type] ?? 1.0

        // Highest state weight wins
        var stateW = cfg.state.fresh
        if context.isReview { stateW = max(stateW, cfg.state.review) }
        if context.isSpacedFollowUp { stateW = max(stateW, cfg.state.spfu) }
        if context.isCurveball { stateW = max(stateW, cfg.state.curveball) }

        let depthW = cfg.depthWeights[context.difficulty] ?? 1.0

        let struggle = cfg.struggle.base
            + (signals.latencySeconds / cfg.struggle.latencyDivisor)
            + (signals.primerUsed ? cfg.struggle.primerUsed : 0.0)
            + (Double(signals.optionChanges) * cfg.struggle.optionChange)

        let raw = cfg.base * typeW * stateW * depthW * struggle
        return raw
    }

    func bcalForLesson(items: [(BCalQuestionContext, BCalQuestionSignals)]) -> Int {
        let sum = items.map { bcalForQuestion(context: $0.0, signals: $0.1) }.reduce(0.0, +)
        let scaled = config.lessonScale * sum
        let clamped = min(Double(config.lessonClamp.upperBound), max(Double(config.lessonClamp.lowerBound), scaled))
        return Int(round(clamped))
    }
}

