import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var anchoredQuery: HKAnchoredObjectQuery?

    @Published var heartRate: Double? = nil
    @Published var lastUpdated: Date? = nil
    @Published var authorizationStatus: AuthStatus = .notDetermined
    @Published var errorMessage: String? = nil
    @Published var airPodsSource: String? = nil

    var mqttManager: MQTTManager?

    enum AuthStatus {
        case notDetermined, authorized, denied, unavailable
    }

    private let heartRateType = HKQuantityType(.heartRate)

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
            // NOTE: For read-only types Apple always returns .notDetermined from
            // authorizationStatus(for:) to protect user privacy — never use that
            // to gate startMonitoring(). Just proceed after a successful request.
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
        // Prefer AirPods Pro source; fall back to most recent sample
        let preferred = samples.first { isAirPods($0.sourceRevision) }
            ?? samples.sorted { $0.startDate > $1.startDate }.first
        guard let sample = preferred else { return }
        heartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
        lastUpdated = sample.startDate
        airPodsSource = isAirPods(sample.sourceRevision) ? sample.sourceRevision.source.name : nil
        errorMessage = nil

        if let bpm = heartRate, let ts = lastUpdated {
            mqttManager?.publishHeartRate(bpm, source: airPodsSource, timestamp: ts)
        }
    }

    // AirPods Pro 3 surfaces its source name as "AirPods" in HealthKit.
    private func isAirPods(_ source: HKSourceRevision) -> Bool {
        let name = source.source.name.lowercased()
        return name.contains("airpods") || name.contains("earpods")
    }
}
