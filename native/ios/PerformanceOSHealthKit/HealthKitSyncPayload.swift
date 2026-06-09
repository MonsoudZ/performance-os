import Foundation

struct HealthKitSyncPayload: Encodable {
    let samples: [HealthKitSamplePayload]
}

struct HealthKitSamplePayload: Encodable {
    enum MetricType: String, Encodable {
        case hrvSDNN = "hrv_sdnn_ms"
        case restingHeartRate = "resting_hr_bpm"
        case sleepAsleep = "sleep_asleep"
    }

    let externalID: String
    let metricType: MetricType
    let startedAt: Date
    let endedAt: Date?
    let value: Double
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case externalID = "external_id"
        case metricType = "metric_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case value
        case metadata
    }
}
