import SwiftUI

struct ContentView: View {
    @StateObject private var hkManager = HealthKitManager()
    @StateObject private var mqttManager = MQTTManager()
    @State private var showMQTTSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heartRateCard
                    sourceCard
                    mqttStatusCard
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
        .task {
            hkManager.mqttManager = mqttManager
            await hkManager.requestAuthorization()
        }
        .sheet(isPresented: $showMQTTSettings) {
            MQTTSettingsView(manager: mqttManager)
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

    // MARK: - Subviews

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

    private var mqttStatusCard: some View {
        Button { showMQTTSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: mqttManager.isEnabled
                      ? (mqttManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                      : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(mqttManager.isEnabled
                                     ? (mqttManager.isConnected ? .green : .orange)
                                     : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mqttManager.isEnabled
                         ? (mqttManager.isConnected ? "MQTT Connected" : "MQTT Connecting\u{2026}")
                         : "MQTT Disabled")
                        .font(.subheadline)
                    if mqttManager.isEnabled, mqttManager.messageCount > 0 {
                        Text("\(mqttManager.messageCount) messages sent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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

// MARK: - MQTT Settings

struct MQTTSettingsView: View {
    @ObservedObject var manager: MQTTManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable MQTT", isOn: $manager.isEnabled)
                } footer: {
                    Text("Send heart rate data to an MQTT broker in real time.")
                }

                Section("Broker") {
                    HStack {
                        Text("Host")
                            .frame(width: 50, alignment: .leading)
                        TextField("broker.emqx.io", text: $manager.brokerHost)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("Port")
                            .frame(width: 50, alignment: .leading)
                        TextField("1883", text: $manager.brokerPort)
                            .keyboardType(.numberPad)
                    }
                }

                Section("Topic") {
                    TextField("airpods/heartrate", text: $manager.topic)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Status") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(manager.isConnected ? "Connected" : "Disconnected")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Messages Sent")
                        Spacer()
                        Text("\(manager.messageCount)")
                            .foregroundStyle(.secondary)
                    }
                    if let last = manager.lastPublished {
                        HStack {
                            Text("Last Published")
                            Spacer()
                            Text(last.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if manager.isEnabled {
                    Section {
                        Button("Reconnect") {
                            manager.disconnect()
                            manager.connect()
                        }
                    }
                }
            }
            .navigationTitle("MQTT Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
