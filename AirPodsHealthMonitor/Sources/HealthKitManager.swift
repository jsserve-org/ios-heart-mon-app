import HealthKit
import SwiftUI

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var anchoredQuery: HKAnchoredObjectQuery?

    @Published var heartRate: Double? = nil
    @Published var lastUpdated: Date? = nil
    @Published var authorizationStatus: AuthStatus = .notDetermined
    @Published var errorMessage: String? = nil
    @Published var airPodsSource: String? = nil
    @Published var history: [HeartRateReading] = []
    @Published var stats: HeartRateStats? = nil

    enum AuthStatus {
        case notDetermined, authorized, denied, unavailable
    }

    struct HeartRateReading: Identifiable, Equatable {
        let id = UUID()
        let bpm: Double
        let date: Date
        let source: String?
        var zone: HeartRateZone { HeartRateZone.from(bpm: bpm) }
    }

    struct HeartRateStats {
        let min: Double
        let max: Double
        let average: Double
        let count: Int
    }

    enum HeartRateZone: String, CaseIterable {
        case rest = "Rest"
        case fatBurn = "Fat Burn"
        case cardio = "Cardio"
        case peak = "Peak"
        case extreme = "Extreme"

        static func from(bpm: Double) -> HeartRateZone {
            switch bpm {
            case ..<100: return .rest
            case 100..<140: return .fatBurn
            case 140..<170: return .cardio
            case 170..<200: return .peak
            default: return .extreme
            }
        }

        var color: Color {
            switch self {
            case .rest: return .blue
            case .fatBurn: return .green
            case .cardio: return .yellow
            case .peak: return .orange
            case .extreme: return .red
            }
        }

        var icon: String {
            switch self {
            case .rest: return "bed.double.fill"
            case .fatBurn: return "flame.fill"
            case .cardio: return "bolt.heart.fill"
            case .peak: return "figure.run"
            case .extreme: return "exclamationmark.triangle.fill"
            }
        }
    }

    private let heartRateType = HKQuantityType(.heartRate)
    private let maxHistoryCount = 60

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isHealthKitAvailable else {
            authorizationStatus = .unavailable
            errorMessage = "HealthKit is not available on this device."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [heartRateType])
            authorizationStatus = .authorized
            startMonitoring()
        } catch {
            authorizationStatus = .denied
            errorMessage = "Authorization failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        stopMonitoring()
        setupLiveQuery()
    }

    func stopMonitoring() {
        if let q = anchoredQuery { healthStore.stop(q) }
        anchoredQuery = nil
    }

    func clearHistory() {
        history = []
        stats = nil
    }

    // One anchored query handles both the initial batch and all future updates.
    private func setupLiveQuery() {
        let anchor = HKQueryAnchor(fromValue: 0)
        let q = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, newSamples, _, _, error in
            let samples = newSamples as? [HKQuantitySample]
            let errMsg = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errMsg { self.errorMessage = errMsg; return }
                self.apply(samples: samples)
            }
        }

        q.updateHandler = { [weak self] _, newSamples, _, _, error in
            let samples = newSamples as? [HKQuantitySample]
            let errMsg = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errMsg { self.errorMessage = errMsg; return }
                self.apply(samples: samples)
            }
        }

        anchoredQuery = q
        healthStore.execute(q)
    }

    private func apply(samples: [HKQuantitySample]?) {
        guard let samples, !samples.isEmpty else { return }

        // Deduplicate: only add samples newer than our latest
        let latestDate = history.first?.date ?? .distantPast
        let newSamples = samples
            .filter { $0.startDate > latestDate }
            .sorted { $0.startDate > $1.startDate }

        // Prefer AirPods Pro source; fall back to most recent sample
        let preferred = samples.first { isAirPods($0.sourceRevision) }
            ?? samples.sorted { $0.startDate > $1.startDate }.first
        guard let sample = preferred else { return }

        let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
        heartRate = bpm
        lastUpdated = sample.startDate
        airPodsSource = isAirPods(sample.sourceRevision) ? sample.sourceRevision.source.name : nil
        errorMessage = nil

        // Append new readings to history
        for s in newSamples {
            let value = s.quantity.doubleValue(for: HKUnit(from: "count/min"))
            let reading = HeartRateReading(
                bpm: value,
                date: s.startDate,
                source: isAirPods(s.sourceRevision) ? s.sourceRevision.source.name : nil
            )
            history.insert(reading, at: 0)
        }

        // Trim history
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }

        updateStats()
    }

    private func updateStats() {
        guard !history.isEmpty else { stats = nil; return }
        let values = history.map(\.bpm)
        stats = HeartRateStats(
            min: values.min() ?? 0,
            max: values.max() ?? 0,
            average: values.reduce(0, +) / Double(values.count),
            count: values.count
        )
    }

    // AirPods Pro 3 surfaces its source name as "AirPods" in HealthKit.
    private func isAirPods(_ source: HKSourceRevision) -> Bool {
        let name = source.source.name.lowercased()
        return name.contains("airpods") || name.contains("earpods")
    }
}
