#if os(iOS)
import Foundation
import CoreHaptics
import UIKit

/// Encapsulates the haptic feedback we play when an answer is checked.
/// Success is a single continuous pulse, failure is two quick pulses.
/// Timing and intensity live inside `Configuration` so we can tweak them easily.
final class AnswerHaptics {
    struct Configuration {
        var correctDuration: TimeInterval = 0.3
        var correctIntensity: Float = 0.5
        var correctSharpness: Float = 0.3
        var incorrectFirstPulseDuration: TimeInterval = 0.20
        var incorrectSecondPulseDuration: TimeInterval = 0.30
        var incorrectPulseSpacing: TimeInterval = 0.1
        var incorrectIntensity: Float = 1
        var incorrectSharpness: Float = 0.7
    }

    static let shared = AnswerHaptics()
    var configuration = Configuration()

    private var engine: CHHapticEngine?
    private let engineQueue = DispatchQueue(label: "AnswerHaptics.engineQueue")
    private var supportsCoreHaptics: Bool = false
    private let fallbackGenerator = UINotificationFeedbackGenerator()

    private init() {
        prepareEngineIfNeeded()
    }

    func playCorrect() {
        if let pattern = makeCorrectPattern() {
            play(pattern: pattern)
        } else {
            fallbackGenerator.notificationOccurred(.success)
        }
    }

    func playIncorrect() {
        if let pattern = makeIncorrectPattern() {
            play(pattern: pattern)
        } else {
            fallbackGenerator.notificationOccurred(.error)
        }
    }

    private func prepareEngineIfNeeded() {
        guard !supportsCoreHaptics else { return }
        supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supportsCoreHaptics else { return }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
            engine?.resetHandler = { [weak self] in
                self?.engineQueue.async { self?.restartEngineIfNeeded() }
            }
        } catch {
            supportsCoreHaptics = false
            engine = nil
        }
    }

    private func restartEngineIfNeeded() {
        guard supportsCoreHaptics else { return }
        do {
            try engine?.start()
        } catch {
            supportsCoreHaptics = false
        }
    }

    private func play(pattern: CHHapticPattern) {
        prepareEngineIfNeeded()
        guard supportsCoreHaptics else { return }
        engineQueue.async { [weak self] in
            do {
                guard let player = try self?.engine?.makePlayer(with: pattern) else { return }
                try player.start(atTime: 0)
            } catch {
                self?.supportsCoreHaptics = false
            }
        }
    }

    private func makeCorrectPattern() -> CHHapticPattern? {
        guard supportsCoreHaptics else { return nil }
        let params = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: configuration.correctIntensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: configuration.correctSharpness)
        ]
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: params,
            relativeTime: 0,
            duration: configuration.correctDuration
        )
        return try? CHHapticPattern(events: [event], parameters: [])
    }

    private func makeIncorrectPattern() -> CHHapticPattern? {
        guard supportsCoreHaptics else { return nil }
        let params = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: configuration.incorrectIntensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: configuration.incorrectSharpness)
        ]
        let secondStart = configuration.incorrectFirstPulseDuration + configuration.incorrectPulseSpacing
        let first = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: params,
            relativeTime: 0,
            duration: configuration.incorrectFirstPulseDuration
        )
        let second = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: params,
            relativeTime: secondStart,
            duration: configuration.incorrectSecondPulseDuration
        )
        return try? CHHapticPattern(events: [first, second], parameters: [])
    }
}
#endif
