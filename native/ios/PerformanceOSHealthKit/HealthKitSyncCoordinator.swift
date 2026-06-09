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

    init(
        syncURL: URL,
        accessToken: String,
        healthStore: HKHealthStore = HKHealthStore(),
        session: URLSession = .shared
    ) {
        self.syncURL = syncURL
        self.accessToken = accessToken
        self.healthStore = healthStore
        self.session = session
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
        async let sleep = sleepSamples(since: startDate)

        let (hrvSamples, restingHeartRateSamples, sleepSamples) = try await (hrv, restingHeartRate, sleep)
        let samples = hrvSamples + restingHeartRateSamples + sleepSamples
        guard !samples.isEmpty else { return }

        for batch in samples.chunked(maxCount: 1_000) {
            try await upload(batch)
        }
    }

    private var readTypes: Set<HKObjectType> {
        [hrvType, restingHeartRateType, sleepType]
    }

    private var hrvType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    }

    private var restingHeartRateType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
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

    private var asleepValues: Set<Int> {
        [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
    }

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
