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
    @Published var hrv: Double? = nil
    @Published var trend: Trend = .stable
    @Published var zoneBreakdown: [ZoneBreakdownEntry] = []
    @Published var sessionStart: Date? = nil

    enum AuthStatus {
        case notDetermined, authorized, denied, unavailable
    }

    enum Trend: String {
        case rising = "Rising"
        case falling = "Falling"
        case stable = "Stable"

        var icon: String {
            switch self {
            case .rising: return "arrow.up.right"
            case .falling: return "arrow.down.right"
            case .stable: return "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .rising: return .orange
            case .falling: return .blue
            case .stable: return .white.opacity(0.5)
            }
        }
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

    struct ZoneBreakdownEntry: Identifiable {
        let id = UUID()
        let zone: HeartRateZone
        let count: Int
        var fraction: Double { 0 } // computed externally
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
    private let maxHistoryCount = 120

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var sessionDuration: TimeInterval {
        guard let start = sessionStart else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var maxHR: Double { 220 } // theoretical max for gauge

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
        sessionStart = Date()
        setupLiveQuery()
    }

    func stopMonitoring() {
        if let q = anchoredQuery { healthStore.stop(q) }
        anchoredQuery = nil
    }

    func clearHistory() {
        history = []
        stats = nil
        hrv = nil
        trend = .stable
        zoneBreakdown = []
        sessionStart = Date()
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

        // Start session on first data
        if sessionStart == nil { sessionStart = Date() }

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
        updateHRV()
        updateTrend()
        updateZoneBreakdown()
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

    private func updateHRV() {
        // RMSSD — root mean square of successive differences (ms)
        // Requires at least 3 readings for meaningful value
        guard history.count >= 3 else { hrv = nil; return }
        let recent = history.prefix(20).map(\.bpm)
        var sumSquaredDiffs: Double = 0
        for i in 0..<(recent.count - 1) {
            let diff = recent[i + 1] - recent[i]
            sumSquaredDiffs += diff * diff
        }
        let meanSquare = sumSquaredDiffs / Double(recent.count - 1)
        hrv = sqrt(meanSquare)
    }

    private func updateTrend() {
        guard history.count >= 6 else { trend = .stable; return }
        let recent = Array(history.prefix(10).map(\.bpm))
        let firstHalf = recent.suffix(recent.count / 2).reduce(0, +) / Double(recent.count / 2)
        let secondHalf = recent.prefix(recent.count / 2).reduce(0, +) / Double(recent.count / 2)
        // firstHalf = older readings, secondHalf = newer readings
        let delta = firstHalf - secondHalf // positive = rising (newer is higher in the array = older)
        // Wait — history is newest-first, so prefix = newest, suffix = older
        let newerAvg = recent.prefix(recent.count / 2).reduce(0, +) / Double(recent.count / 2)
        let olderAvg = recent.suffix(recent.count / 2).reduce(0, +) / Double(recent.count / 2)
        let diff = newerAvg - olderAvg
        if diff > 3 {
            trend = .rising
        } else if diff < -3 {
            trend = .falling
        } else {
            trend = .stable
        }
    }

    private func updateZoneBreakdown() {
        guard !history.isEmpty else { zoneBreakdown = []; return }
        var counts: [HeartRateZone: Int] = [:]
        for zone in HeartRateZone.allCases { counts[zone] = 0 }
        for reading in history { counts[reading.zone, default: 0] += 1 }
        let total = Double(history.count)
        zoneBreakdown = HeartRateZone.allCases
            .filter { (counts[$0] ?? 0) > 0 }
            .map { zone in
                ZoneBreakdownEntry(zone: zone, count: counts[zone] ?? 0)
            }
    }

    // AirPods Pro 3 surfaces its source name as "AirPods" in HealthKit.
    private func isAirPods(_ source: HKSourceRevision) -> Bool {
        let name = source.source.name.lowercased()
        return name.contains("airpods") || name.contains("earpods")
    }
}
