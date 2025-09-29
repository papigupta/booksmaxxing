import Foundation
import SwiftData

@Model
final class DailyCognitiveStats {
    var id: UUID = UUID()
    // Start of day (local calendar) used as unique key
    var dayStart: Date = Date()
    var bcalTotal: Int = 0
    var answeredCount: Int = 0
    var correctCount: Int = 0

    init(dayStart: Date) {
        self.id = UUID()
        self.dayStart = dayStart
        self.bcalTotal = 0
    }
}

struct CognitiveStatsService {
    let modelContext: ModelContext

    func addBCalToToday(_ amount: Int) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<DailyCognitiveStats>(
            predicate: #Predicate { $0.dayStart == todayStart }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.bcalTotal += amount
        } else {
            let stats = DailyCognitiveStats(dayStart: todayStart)
            stats.bcalTotal = amount
            modelContext.insert(stats)
        }
        try? modelContext.save()
    }

    func addAnswers(correct: Int, total: Int) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<DailyCognitiveStats>(
            predicate: #Predicate { $0.dayStart == todayStart }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.answeredCount += total
            existing.correctCount += correct
        } else {
            let stats = DailyCognitiveStats(dayStart: todayStart)
            stats.answeredCount = total
            stats.correctCount = correct
            modelContext.insert(stats)
        }
        try? modelContext.save()
    }

    func todayBCalTotal() -> Int {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<DailyCognitiveStats>(
            predicate: #Predicate { $0.dayStart == todayStart }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing.bcalTotal
        }
        return 0
    }

    func todayAccuracy() -> (correct: Int, total: Int, percent: Int) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<DailyCognitiveStats>(
            predicate: #Predicate { $0.dayStart == todayStart }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            let total = max(0, existing.answeredCount)
            let correct = max(0, existing.correctCount)
            let percent = total > 0 ? Int(round(100.0 * Double(correct) / Double(total))) : 0
            return (correct, total, percent)
        }
        return (0, 0, 0)
    }
}
