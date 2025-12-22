import Foundation
import SwiftData

@Model
final class AnalyticsSyncJob {
    var id: UUID = UUID()
    var payloadData: Data = Foundation.Data()
    var enqueuedAt: Date = Date()
    var retryCount: Int = 0
    var nextAttemptAt: Date = Date()
    var lastErrorMessage: String?

    init(payload: AnalyticsPublicRecordPayload, encoder: JSONEncoder = JSONEncoder()) {
        self.id = UUID()
        self.enqueuedAt = Date()
        self.retryCount = 0
        self.nextAttemptAt = Date()
        if let encoded = try? encoder.encode(payload) {
            self.payloadData = encoded
        } else {
            self.payloadData = Data()
            self.lastErrorMessage = "Failed to encode payload"
        }
    }

    func payload(decoder: JSONDecoder = JSONDecoder()) -> AnalyticsPublicRecordPayload? {
        try? decoder.decode(AnalyticsPublicRecordPayload.self, from: payloadData)
    }
}
