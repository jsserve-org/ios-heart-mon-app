import SwiftUI
import Charts
import WatchConnectivity

struct ContentView: View {
    @StateObject private var hkManager = HealthKitManager()
    @StateObject private var mqttManager = MQTTManager()
    @StateObject private var httpManager = HTTPManager()
    @StateObject private var watchManager = WatchManager()

    var body: some View {
        TabView {
            Tab("Heart Rate", systemImage: "heart.fill") {
                HeartRateTab(hkManager: hkManager, mqttManager: mqttManager, httpManager: httpManager)
            }
            Tab("History", systemImage: "chart.xyaxis.line") {
                HistoryTab(hkManager: hkManager)
            }
            Tab("Connections", systemImage: "antenna.radiowaves.left.and.right") {
                ConnectionsTab(mqttManager: mqttManager, httpManager: httpManager)
            }
            Tab("Watch", systemImage: "applewatch.watchface") {
                WatchTab(watchManager: watchManager)
            }
            Tab("Settings", systemImage: "gear") {
                SettingsTab(hkManager: hkManager)
            }
        }
        .task {
            hkManager.mqttManager = mqttManager
            hkManager.httpManager = httpManager
            await hkManager.requestAuthorization()
        }
        .alert("Error", isPresented: Binding(
            get: { hkManager.errorMessage != nil },
            set: { if !$0 { hkManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { hkManager.errorMessage = nil }
        } message: {
            Text(hkManager.errorMessage ?? "")
        }
    }
}

// MARK: - Heart Rate Tab

struct HeartRateTab: View {
    @ObservedObject var hkManager: HealthKitManager
    @ObservedObject var mqttManager: MQTTManager
    @ObservedObject var httpManager: HTTPManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heartRateCard
                    statsCard
                    sourceCard
                    connectionSummary
                    footerTimestamp
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Heart Rate")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label("AirPods Pro 3", systemImage: "airpodspro")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    statusDot
                }
            }
        }
    }

    private var statusDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hkManager.heartRate != nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(hkManager.heartRate != nil ? "Live" : "Waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heartRateCard: some View {
        VStack(spacing: 12) {
            PulsingHeart(bpm: hkManager.heartRate)

            if let bpm = hkManager.heartRate {
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(Int(bpm))")
                        .font(.system(size: 80, weight: .thin, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: bpm)
                    Text("BPM")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }
            } else {
                placeholderBPM
            }

            Text("Heart Rate")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tracking(2)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    private var statsCard: some View {
        Group {
            if !hkManager.history.isEmpty {
                HStack(spacing: 0) {
                    statItem(label: "MIN", value: hkManager.minBPM, color: .blue)
                    Divider().frame(height: 40)
                    statItem(label: "AVG", value: hkManager.avgBPM, color: .green)
                    Divider().frame(height: 40)
                    statItem(label: "MAX", value: hkManager.maxBPM, color: .red)
                }
                .padding(.vertical, 16)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    private func statItem(label: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(value.map { "\(Int($0))" } ?? "--")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderBPM: some View {
        Group {
            switch hkManager.authorizationStatus {
            case .denied:
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Access Denied")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Open Settings \u{2192} Privacy \u{2192} Health\nand allow Heart Rate access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            case .unavailable:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text("HealthKit unavailable")
                        .foregroundStyle(.red)
                }
            default:
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Waiting for data\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 120)
    }

    private var sourceCard: some View {
        Group {
            if let source = hkManager.airPodsSource {
                Label("Source: \(source)", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            } else if hkManager.heartRate != nil {
                Label("Source: Other device (pair AirPods Pro 3 for direct data)", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    private var connectionSummary: some View {
        VStack(spacing: 8) {
            if mqttManager.isEnabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(mqttManager.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(mqttManager.isConnected ? "MQTT Connected" : "MQTT Connecting\u{2026}")
                        .font(.caption)
                    if mqttManager.messageCount > 0 {
                        Spacer()
                        Text("\(mqttManager.messageCount) sent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if httpManager.isEnabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(httpManager.lastError == nil ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("HTTP \(httpManager.lastError == nil ? "Active" : "Error")")
                        .font(.caption)
                    if httpManager.messageCount > 0 {
                        Spacer()
                        Text("\(httpManager.messageCount) sent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var footerTimestamp: some View {
        Group {
            if let date = hkManager.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    @ObservedObject var hkManager: HealthKitManager
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if hkManager.history.count >= 2 {
                        chartCard
                        zoneCard
                    } else {
                        ContentUnavailableView(
                            "No History Yet",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Heart rate samples will appear here as they are recorded.")
                        )
                    }

                    recentSamplesList
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("History")
            .toolbar {
                if !hkManager.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            exportURL = hkManager.exportCSV()
                            showExportSheet = exportURL != nil
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate Over Time")
                .font(.subheadline.bold())
                .padding(.horizontal)

            Chart(hkManager.history) { sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .red], startPoint: .bottom, endPoint: .top)
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", sample.date),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 200)
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var zoneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate Zones")
                .font(.subheadline.bold())

            let zones = computeZones()
            ForEach(zones, id: \.name) { zone in
                HStack {
                    Circle()
                        .fill(zone.color)
                        .frame(width: 10, height: 10)
                    Text(zone.name)
                        .font(.caption)
                    Spacer()
                    Text("\(zone.count) samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        let fraction = hkManager.history.isEmpty ? 0.0 : Double(zone.count) / Double(hkManager.history.count)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(zone.color.opacity(0.6))
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(width: 80, height: 8)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private struct Zone {
        let name: String
        let color: Color
        let count: Int
    }

    private func computeZones() -> [Zone] {
        var resting = 0, moderate = 0, elevated = 0, high = 0
        for s in hkManager.history {
            switch s.bpm {
            case ..<60: resting += 1
            case 60..<100: moderate += 1
            case 100..<140: elevated += 1
            default: high += 1
            }
        }
        return [
            Zone(name: "Resting (<60)", color: .blue, count: resting),
            Zone(name: "Normal (60-99)", color: .green, count: moderate),
            Zone(name: "Elevated (100-139)", color: .orange, count: elevated),
            Zone(name: "High (140+)", color: .red, count: high),
        ]
    }

    private var recentSamplesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hkManager.history.isEmpty {
                Text("Recent Readings")
                    .font(.subheadline.bold())
                    .padding(.horizontal)

                let recent = hkManager.history.suffix(20).reversed()
                ForEach(Array(recent)) { sample in
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(colorForBPM(sample.bpm))
                        Text("\(Int(sample.bpm)) BPM")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        if let src = sample.source {
                            Text(src)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(sample.date.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func colorForBPM(_ bpm: Double) -> Color {
        switch bpm {
        case ..<60: return .blue
        case 60..<100: return .green
        case 100..<140: return .orange
        default: return .red
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Connections Tab

struct ConnectionsTab: View {
    @ObservedObject var mqttManager: MQTTManager
    @ObservedObject var httpManager: HTTPManager

    var body: some View {
        NavigationStack {
            Form {
                // MQTT Section
                Section {
                    Toggle("Enable MQTT", isOn: $mqttManager.isEnabled)
                } header: {
                    Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                } footer: {
                    Text("Send heart rate data to an MQTT broker in real time.")
                }

                if mqttManager.isEnabled {
                    Section("Broker") {
                        HStack {
                            Text("Host")
                                .frame(width: 50, alignment: .leading)
                            TextField("broker.emqx.io", text: $mqttManager.brokerHost)
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        HStack {
                            Text("Port")
                                .frame(width: 50, alignment: .leading)
                            TextField("1883", text: $mqttManager.brokerPort)
                                .keyboardType(.numberPad)
                        }
                    }

                    Section("Authentication") {
                        HStack {
                            Text("User")
                                .frame(width: 50, alignment: .leading)
                            TextField("Optional", text: $mqttManager.username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        HStack {
                            Text("Pass")
                                .frame(width: 50, alignment: .leading)
                            SecureField("Optional", text: $mqttManager.password)
                        }
                    }

                    Section("Client") {
                        HStack {
                            Text("Name")
                                .frame(width: 50, alignment: .leading)
                            TextField("AirPodsMon", text: $mqttManager.clientName)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        TextField("airpods/heartrate", text: $mqttManager.topic)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Section("MQTT Status") {
                        HStack {
                            Text("Connection")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(mqttManager.isConnected ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(mqttManager.isConnected ? "Connected" : "Disconnected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text("Messages Sent")
                            Spacer()
                            Text("\(mqttManager.messageCount)")
                                .foregroundStyle(.secondary)
                        }
                        if let last = mqttManager.lastPublished {
                            HStack {
                                Text("Last Published")
                                Spacer()
                                Text(last.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Reconnect") {
                            mqttManager.disconnect()
                            mqttManager.connect()
                        }
                    }
                }

                // HTTP Section
                Section {
                    Toggle("Enable HTTP", isOn: $httpManager.isEnabled)
                } header: {
                    Label("HTTP", systemImage: "globe")
                } footer: {
                    Text("POST heart rate data as JSON to an HTTP endpoint.")
                }

                if httpManager.isEnabled {
                    Section("Endpoint") {
                        TextField("https://example.com/heartrate", text: $httpManager.endpointURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    Section("Authorization") {
                        SecureField("Bearer token (optional)", text: $httpManager.bearerToken)
                    }

                    Section("HTTP Status") {
                        HStack {
                            Text("Messages Sent")
                            Spacer()
                            Text("\(httpManager.messageCount)")
                                .foregroundStyle(.secondary)
                        }
                        if let last = httpManager.lastPublished {
                            HStack {
                                Text("Last Published")
                                Spacer()
                                Text(last.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let error = httpManager.lastError {
                            HStack {
                                Text("Last Error")
                                Spacer()
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connections")
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @ObservedObject var hkManager: HealthKitManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Heart Rate Alerts", isOn: $hkManager.alertsEnabled)
                } header: {
                    Label("Alerts", systemImage: "bell.badge")
                } footer: {
                    Text("Get notified when your heart rate goes above or below your thresholds.")
                }

                if hkManager.alertsEnabled {
                    Section("Thresholds") {
                        HStack {
                            Image(systemName: "arrow.up.heart.fill")
                                .foregroundStyle(.red)
                            Text("High BPM")
                            Spacer()
                            Text("\(Int(hkManager.highBPMThreshold))")
                                .foregroundStyle(.secondary)
                                .frame(width: 40)
                        }
                        Slider(value: $hkManager.highBPMThreshold, in: 80...200, step: 5)
                            .tint(.red)

                        HStack {
                            Image(systemName: "arrow.down.heart.fill")
                                .foregroundStyle(.blue)
                            Text("Low BPM")
                            Spacer()
                            Text("\(Int(hkManager.lowBPMThreshold))")
                                .foregroundStyle(.secondary)
                                .frame(width: 40)
                        }
                        Slider(value: $hkManager.lowBPMThreshold, in: 30...70, step: 5)
                            .tint(.blue)
                    }

                    Section {
                        Button("Request Notification Permission") {
                            Task { await hkManager.requestNotificationPermission() }
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Samples Recorded")
                        Spacer()
                        Text("\(hkManager.history.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Watch Tab

@MainActor
final class WatchManager: NSObject, ObservableObject {
    @Published var isPaired = false
    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastHeartRateSent: Date?
    @Published var isSupported = false

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            isSupported = true
            let s = WCSession.default
            s.delegate = self
            s.activate()
            session = s
        }
    }

    func sendHeartRate(_ bpm: Double, source: String?, timestamp: Date) {
        guard let session, session.isReachable else { return }
        let message: [String: Any] = [
            "bpm": round(bpm * 10) / 10,
            "source": source ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        session.sendMessage(message, replyHandler: nil) { _ in }
        lastHeartRateSent = Date()
    }
}

extension WatchManager: @preconcurrency WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let paired = session.isPaired
        let reachable = session.isReachable
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = paired
            self.isReachable = reachable
            self.isWatchAppInstalled = installed
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
        }
    }
}

struct WatchTab: View {
    @ObservedObject var watchManager: WatchManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("WatchConnectivity")
                        Spacer()
                        Text(watchManager.isSupported ? "Supported" : "Not Available")
                            .foregroundStyle(watchManager.isSupported ? .green : .red)
                    }
                } footer: {
                    Text("Requires a paired Apple Watch with a companion app.")
                }

                if watchManager.isSupported {
                    Section("Watch Status") {
                        statusRow("Paired", value: watchManager.isPaired)
                        statusRow("Reachable", value: watchManager.isReachable)
                        statusRow("App Installed", value: watchManager.isWatchAppInstalled)
                    }

                    if let last = watchManager.lastHeartRateSent {
                        Section("Activity") {
                            HStack {
                                Text("Last Sent")
                                Spacer()
                                Text(last.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !watchManager.isWatchAppInstalled {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Companion App Needed", systemImage: "applewatch.and.arrow.forward")
                                    .font(.subheadline.bold())
                                Text("Install the AirPods Health Monitor watch app on your Apple Watch to see heart rate data on your wrist.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Apple Watch")
        }
    }

    private func statusRow(_ label: String, value: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(value ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(value ? "Yes" : "No")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pulsing Heart

struct PulsingHeart: View {
    let bpm: Double?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 52))
            .foregroundStyle(
                LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .scaleEffect(scale)
            .onAppear { startPulsing() }
            .onChange(of: bpm) { startPulsing() }
    }

    private func startPulsing() {
        guard let bpm, bpm > 0 else { return }
        let interval = 60.0 / bpm
        withAnimation(.easeInOut(duration: interval * 0.3)) { scale = 1.18 }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval * 0.3) {
            withAnimation(.easeInOut(duration: interval * 0.3)) { scale = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * 0.7) {
                startPulsing()
            }
        }
    }
}

#Preview {
    ContentView()
}
