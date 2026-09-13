import Foundation
import HealthKit

actor HealthKitSyncCoordinator {
    enum SyncError: Error {
        case healthDataUnavailable
        case invalidResponse
    }

    private let healthStore: HKHealthStore
    private let session: URLSession
    private let syncURL: URL
    private let accessToken: String
    private let encoder: JSONEncoder
    private let calendar: Calendar

    init(
        syncURL: URL,
        accessToken: String,
        healthStore: HKHealthStore = HKHealthStore(),
        session: URLSession = .shared,
        calendar: Calendar = .current
    ) {
        self.syncURL = syncURL
        self.accessToken = accessToken
        self.healthStore = healthStore
        self.session = session
        self.calendar = calendar
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SyncError.healthDataUnavailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func sync(since startDate: Date = Calendar.current.date(byAdding: .day, value: -14, to: .now)!) async throws {
        async let hrv = quantitySamples(
            type: hrvType,
            metricType: .hrvSDNN,
            unit: .secondUnit(with: .milli),
            since: startDate
        )
        async let restingHeartRate = quantitySamples(
            type: restingHeartRateType,
            metricType: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            since: startDate
        )
        async let bodyMass = quantitySamples(
            type: bodyMassType,
            metricType: .bodyMass,
            unit: .gramUnit(with: .kilo),
            since: startDate
        )
        async let sleep = sleepSamples(since: startDate)
        async let workouts = workoutSamples(since: startDate)
        async let steps = dailyTotals(
            type: stepCountType,
            metricType: .stepCount,
            unit: .count(),
            since: startDate
        )
        async let activeEnergy = dailyTotals(
            type: activeEnergyType,
            metricType: .activeEnergy,
            unit: .kilocalorie(),
            since: startDate
        )
        async let basalEnergy = dailyTotals(
            type: basalEnergyType,
            metricType: .basalEnergy,
            unit: .kilocalorie(),
            since: startDate
        )

        let samples = try await hrv
            + restingHeartRate
            + bodyMass
            + sleep
            + workouts
            + steps
            + activeEnergy
            + basalEnergy
        guard !samples.isEmpty else { return }

        for batch in samples.chunked(maxCount: 1_000) {
            try await upload(batch)
        }
    }

    private var readTypes: Set<HKObjectType> {
        [
            hrvType,
            restingHeartRateType,
            bodyMassType,
            stepCountType,
            activeEnergyType,
            basalEnergyType,
            heartRateType,
            sleepType,
            HKObjectType.workoutType()
        ]
    }

    private var hrvType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    }

    private var restingHeartRateType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
    }

    private var bodyMassType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .bodyMass)!
    }

    private var stepCountType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .stepCount)!
    }

    private var activeEnergyType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    }

    private var basalEnergyType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
    }

    private var heartRateType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .heartRate)!
    }

    private var sleepType: HKCategoryType {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    }

    private func quantitySamples(
        type: HKQuantityType,
        metricType: HealthKitSamplePayload.MetricType,
        unit: HKUnit,
        since startDate: Date
    ) async throws -> [HealthKitSamplePayload] {
        let samples = try await samples(type: type, since: startDate)
        return samples.compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            return HealthKitSamplePayload(
                externalID: quantitySample.uuid.uuidString,
                metricType: metricType,
                startedAt: quantitySample.startDate,
                endedAt: quantitySample.endDate,
                value: quantitySample.quantity.doubleValue(for: unit),
                metadata: sourceMetadata(for: quantitySample)
            )
        }
    }

    /// Steps and energy arrive as hundreds of fragments a day. Summing them on
    /// device and sending one row per day keeps a fortnight's sync inside a
    /// single batch — but a day's total is still moving while the day is being
    /// lived, so the external ID is the date rather than a sample UUID and the
    /// server treats a later send of the same day as a correction.
    private func dailyTotals(
        type: HKQuantityType,
        metricType: HealthKitSamplePayload.MetricType,
        unit: HKUnit,
        since startDate: Date
    ) async throws -> [HealthKitSamplePayload] {
        let anchor = calendar.startOfDay(for: startDate)
        let collection = try await statistics(
            type: type,
            since: anchor,
            interval: DateComponents(day: 1)
        )

        var payloads: [HealthKitSamplePayload] = []
        collection.enumerateStatistics(from: anchor, to: .now) { statistics, _ in
            guard let total = statistics.sumQuantity()?.doubleValue(for: unit), total > 0 else { return }

            payloads.append(
                HealthKitSamplePayload(
                    externalID: "\(metricType.rawValue):\(Self.dayFormatter.string(from: statistics.startDate))",
                    metricType: metricType,
                    startedAt: statistics.startDate,
                    endedAt: statistics.endDate,
                    value: total,
                    metadata: [:]
                )
            )
        }
        return payloads
    }

    private func sleepSamples(since startDate: Date) async throws -> [HealthKitSamplePayload] {
        let samples = try await samples(type: sleepType, since: startDate)
        return samples.compactMap { sample in
            guard
                let categorySample = sample as? HKCategorySample,
                asleepValues.contains(categorySample.value)
            else {
                return nil
            }

            return HealthKitSamplePayload(
                externalID: categorySample.uuid.uuidString,
                metricType: .sleepAsleep,
                startedAt: categorySample.startDate,
                endedAt: categorySample.endDate,
                value: categorySample.endDate.timeIntervalSince(categorySample.startDate) / 60,
                metadata: sourceMetadata(for: categorySample)
            )
        }
    }

    /// A workout's shape — what it was, how far, how hard — rides in metadata,
    /// because it is the only metric that has a shape. `value` stays the one
    /// thing every metric has: a number in the unit the server expects, here the
    /// workout's own elapsed duration rather than the wall-clock span, so a
    /// paused run does not count the time spent stopped.
    private func workoutSamples(since startDate: Date) async throws -> [HealthKitSamplePayload] {
        let samples = try await samples(type: HKObjectType.workoutType(), since: startDate)
        return samples.compactMap { sample in
            guard let workout = sample as? HKWorkout, workout.duration > 0 else { return nil }

            var metadata = sourceMetadata(for: workout)
            metadata["activity_type"] = workout.workoutActivityType.performanceOSActivityType
            if let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 0 {
                metadata["distance_meters"] = String(Int(meters.rounded()))
            }
            if let averageHeartRate = workout
                .statistics(for: heartRateType)?
                .averageQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())), averageHeartRate > 0 {
                metadata["avg_hr_bpm"] = String(Int(averageHeartRate.rounded()))
            }

            return HealthKitSamplePayload(
                externalID: workout.uuid.uuidString,
                metricType: .workout,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                value: workout.duration,
                metadata: metadata
            )
        }
    }

    private var asleepValues: Set<Int> {
        [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func samples(type: HKSampleType, since startDate: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func statistics(
        type: HKQuantityType,
        since startDate: Date,
        interval: DateComponents
    ) async throws -> HKStatisticsCollection {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startDate, end: nil),
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let collection {
                    continuation.resume(returning: collection)
                } else {
                    continuation.resume(throwing: error ?? SyncError.invalidResponse)
                }
            }
            healthStore.execute(query)
        }
    }

    private func sourceMetadata(for sample: HKSample) -> [String: String] {
        [
            "source_bundle": sample.sourceRevision.source.bundleIdentifier,
            "source_name": sample.sourceRevision.source.name
        ]
    }

    private func upload(_ samples: [HealthKitSamplePayload]) async throws {
        var request = URLRequest(url: syncURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(HealthKitSyncPayload(samples: samples))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw SyncError.invalidResponse
        }
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maxCount).map {
            Array(self[$0..<Swift.min($0 + maxCount, count)])
        }
    }
}
