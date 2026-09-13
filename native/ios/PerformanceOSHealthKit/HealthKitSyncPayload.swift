import Foundation
import HealthKit

struct HealthKitSyncPayload: Encodable {
    let samples: [HealthKitSamplePayload]
}

struct HealthKitSamplePayload: Encodable {
    enum MetricType: String, Encodable {
        case hrvSDNN = "hrv_sdnn_ms"
        case restingHeartRate = "resting_hr_bpm"
        case sleepAsleep = "sleep_asleep"
        case workout = "workout"
        case stepCount = "step_count"
        case activeEnergy = "active_energy_kcal"
        case basalEnergy = "basal_energy_kcal"
        case bodyMass = "body_mass_kg"
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

extension HKWorkoutActivityType {
    /// HealthKit's taxonomy has a hundred-odd cases and PerformanceOS has eight.
    /// The mapping lives here rather than on the server because this enum is the
    /// thing that changes when Apple ships a new activity; anything unrecognized
    /// is still a session worth counting, so it syncs as "other".
    var performanceOSActivityType: String {
        switch self {
        case .running, .trackAndField: return "run"
        case .cycling, .handCycling: return "bike"
        case .rowing: return "row"
        case .swimming, .swimBikeRun: return "swim"
        case .walking, .hiking: return "walk"
        case .jumpRope: return "jump"
        case .crossTraining, .highIntensityIntervalTraining: return "plyometric"
        default: return "other"
        }
    }
}
