import HealthKit
import UserNotifications

struct HeartRateSample: Identifiable {
    let id = UUID()
    let bpm: Double
    let date: Date
    let source: String?
}

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var anchoredQuery: HKAnchoredObjectQuery?

    @Published var heartRate: Double? = nil
    @Published var lastUpdated: Date? = nil
    @Published var authorizationStatus: AuthStatus = .notDetermined
    @Published var errorMessage: String? = nil
    @Published var airPodsSource: String? = nil
    @Published var history: [HeartRateSample] = []

    var mqttManager: MQTTManager?
    var httpManager: HTTPManager?

    // Alerts
    @Published var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alerts_enabled") }
    }
    @Published var highBPMThreshold: Double {
        didSet { UserDefaults.standard.set(highBPMThreshold, forKey: "alert_high_bpm") }
    }
    @Published var lowBPMThreshold: Double {
        didSet { UserDefaults.standard.set(lowBPMThreshold, forKey: "alert_low_bpm") }
    }
    private var lastAlertDate: Date?

    // Stats
    var minBPM: Double? { history.isEmpty ? nil : history.map(\.bpm).min() }
    var maxBPM: Double? { history.isEmpty ? nil : history.map(\.bpm).max() }
    var avgBPM: Double? {
        guard !history.isEmpty else { return nil }
        return history.map(\.bpm).reduce(0, +) / Double(history.count)
    }

    enum AuthStatus {
        case notDetermined, authorized, denied, unavailable
    }

    private let heartRateType = HKQuantityType(.heartRate)
    private static let maxHistory = 500

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init() {
        let defaults = UserDefaults.standard
        alertsEnabled = defaults.bool(forKey: "alerts_enabled")
        highBPMThreshold = defaults.object(forKey: "alert_high_bpm") as? Double ?? 120
        lowBPMThreshold = defaults.object(forKey: "alert_low_bpm") as? Double ?? 50
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

        if alertsEnabled {
            await requestNotificationPermission()
        }
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound])
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
        let preferred = samples.first { isAirPods($0.sourceRevision) }
            ?? samples.sorted { $0.startDate > $1.startDate }.first
        guard let sample = preferred else { return }
        let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
        let sourceName = isAirPods(sample.sourceRevision) ? sample.sourceRevision.source.name : nil

        heartRate = bpm
        lastUpdated = sample.startDate
        airPodsSource = sourceName
        errorMessage = nil

        // Record history
        let record = HeartRateSample(bpm: bpm, date: sample.startDate, source: sourceName)
        history.append(record)
        if history.count > Self.maxHistory {
            history.removeFirst(history.count - Self.maxHistory)
        }

        // Check alerts
        checkAlerts(bpm: bpm)

        // Publish
        if let ts = lastUpdated {
            mqttManager?.publishHeartRate(bpm, source: airPodsSource, timestamp: ts)
            httpManager?.publishHeartRate(bpm, source: airPodsSource, timestamp: ts)
        }
    }

    // MARK: - Alerts

    private func checkAlerts(bpm: Double) {
        guard alertsEnabled else { return }
        // Throttle: one alert per 60 seconds
        if let last = lastAlertDate, Date().timeIntervalSince(last) < 60 { return }

        var message: String?
        if bpm >= highBPMThreshold {
            message = "High heart rate: \(Int(bpm)) BPM (threshold: \(Int(highBPMThreshold)))"
        } else if bpm <= lowBPMThreshold {
            message = "Low heart rate: \(Int(bpm)) BPM (threshold: \(Int(lowBPMThreshold)))"
        }

        guard let message else { return }
        lastAlertDate = Date()

        let content = UNMutableNotificationContent()
        content.title = "Heart Rate Alert"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Export

    func exportCSV() -> URL? {
        guard !history.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        var csv = "timestamp,bpm,source\n"
        for sample in history {
            let ts = formatter.string(from: sample.date)
            let src = sample.source ?? "unknown"
            csv += "\(ts),\(sample.bpm),\(src)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("heartrate_export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    private func isAirPods(_ source: HKSourceRevision) -> Bool {
        let name = source.source.name.lowercased()
        return name.contains("airpods") || name.contains("earpods")
    }
}
