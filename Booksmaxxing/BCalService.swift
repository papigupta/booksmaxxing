import Foundation
import SwiftData

@Model
final class DailyCognitiveStats {
    var id: UUID = UUID()
    // Start of day (local calendar) used as unique key
    var dayStart: Date = Date()
    var bcalTotal: Int = 0

    init(dayStart: Date) {
        self.id = UUID()
        self.dayStart = dayStart
        self.bcalTotal = 0
    }
}

struct BCalService {
    let modelContext: ModelContext

    func addToToday(_ amount: Int) {
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
    
    func todayTotal() -> Int {
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
}
