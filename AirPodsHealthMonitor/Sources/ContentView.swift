import SwiftUI

struct ContentView: View {
    @StateObject private var hkManager = HealthKitManager()
    @State private var showHistory = false

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                headerBar
                    .padding(.top, 8)
                Spacer()
                heartRateDisplay
                Spacer()
                if hkManager.heartRate != nil {
                    zoneIndicator
                    statsCards
                }
                Spacer()
                footerBar
                    .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet(readings: hkManager.history)
        }
        .task {
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

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.03, blue: 0.10),
                    Color(red: 0.08, green: 0.04, blue: 0.18),
                    Color(red: 0.04, green: 0.06, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.15), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 400
            )
            RadialGradient(
                colors: [Color.red.opacity(0.08), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "airpodspro")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Text("AirPods Pro 3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            HStack(spacing: 12) {
                statusDot
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .disabled(hkManager.history.isEmpty)
            }
        }
        .padding(.horizontal, 24)
    }

    private var statusDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hkManager.heartRate != nil ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .fill(hkManager.heartRate != nil ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                        .opacity(0.6)
                        .scaleEffect(hkManager.heartRate != nil ? 2.0 : 1.0)
                        .animation(
                            hkManager.heartRate != nil
                                ? .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                                : .default,
                            value: hkManager.heartRate != nil
                        )
                )
            Text(hkManager.heartRate != nil ? "Live" : "Waiting")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Heart Rate Display

    private var heartRateDisplay: some View {
        VStack(spacing: 12) {
            EnhancedPulsingHeart(bpm: hkManager.heartRate)
                .onTapGesture {
                    if hkManager.heartRate != nil {
                        HapticManager.shared.heartbeat()
                    }
                }

            if let bpm = hkManager.heartRate {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(bpm))")
                        .font(.system(size: 96, weight: .thin, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: bpm)
                    Text("BPM")
                        .font(.title3.weight(.light))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 14)
                }

                SparklineChart(values: hkManager.history.prefix(30).map(\.bpm).reversed())
                    .frame(height: 40)
                    .padding(.horizontal, 48)
                    .opacity(0.7)
            } else {
                placeholderBPM
            }

            Text("Heart Rate")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(3)
                .textCase(.uppercase)
        }
    }

    private var placeholderBPM: some View {
        Group {
            switch hkManager.authorizationStatus {
            case .denied:
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Access Denied")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.orange)
                    Text("Open Settings \u{2192} Privacy \u{2192} Health\nand allow Heart Rate access.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
            case .unavailable:
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.red)
                    Text("HealthKit Unavailable")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.red)
                }
            default:
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                        .scaleEffect(1.3)
                    Text("Waiting for data\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(height: 140)
    }

    // MARK: - Zone Indicator

    private var zoneIndicator: some View {
        Group {
            if let bpm = hkManager.heartRate {
                let zone = HealthKitManager.HeartRateZone.from(bpm: bpm)
                HStack(spacing: 8) {
                    Image(systemName: zone.icon)
                        .font(.caption)
                    Text(zone.rawValue)
                        .font(.caption.weight(.semibold))
                    Text("Zone")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .foregroundStyle(zone.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(zone.color.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(zone.color.opacity(0.25), lineWidth: 1)
                )
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.5), value: zone)
                .onChange(of: zone) { _, _ in
                    HapticManager.shared.zoneChange()
                }
            }
        }
    }

    // MARK: - Stats Cards

    private var statsCards: some View {
        Group {
            if let stats = hkManager.stats, stats.count > 1 {
                HStack(spacing: 12) {
                    statCard(label: "Min", value: "\(Int(stats.min))", color: .blue)
                    statCard(label: "Avg", value: "\(Int(stats.average))", color: .white)
                    statCard(label: "Max", value: "\(Int(stats.max))", color: .red)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if let date = hkManager.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
            }
            Spacer()
            if hkManager.history.count > 1 {
                Text("\(hkManager.history.count) readings")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Enhanced Pulsing Heart

struct EnhancedPulsingHeart: View {
    let bpm: Double?
    @State private var scale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Outer glow
            Image(systemName: "heart.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red.opacity(glowOpacity * 0.3))
                .blur(radius: 20)
                .scaleEffect(scale * 1.2)

            // Main heart
            Image(systemName: "heart.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink, .red, .red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(scale)
                .shadow(color: .red.opacity(glowOpacity * 0.5), radius: 12, y: 4)
        }
        .onAppear { startPulsing() }
        .onChange(of: bpm) { _, _ in startPulsing() }
    }

    private func startPulsing() {
        guard let bpm, bpm > 0 else {
            withAnimation(.easeOut(duration: 0.5)) {
                scale = 1.0
                glowOpacity = 0.0
            }
            return
        }
        let interval = 60.0 / bpm

        // Beat: expand + glow
        withAnimation(.easeOut(duration: interval * 0.15)) {
            scale = 1.2
            glowOpacity = 1.0
        }

        // Haptic on beat
        HapticManager.shared.heartbeat()

        // Relax: contract
        DispatchQueue.main.asyncAfter(deadline: .now() + interval * 0.15) {
            withAnimation(.easeInOut(duration: interval * 0.25)) {
                scale = 0.95
                glowOpacity = 0.3
            }
        }

        // Settle
        DispatchQueue.main.asyncAfter(deadline: .now() + interval * 0.4) {
            withAnimation(.easeOut(duration: interval * 0.2)) {
                scale = 1.0
                glowOpacity = 0.0
            }
        }

        // Next beat
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            startPulsing()
        }
    }
}

// MARK: - Sparkline Chart

struct SparklineChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let minVal = values.min() ?? 0
                let maxVal = values.max() ?? 100
                let range = max(maxVal - minVal, 1)

                Path { path in
                    for (i, val) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((val - minVal) / range))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [.pink.opacity(0.8), .red.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )

                // Fill gradient under the line
                Path { path in
                    for (i, val) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((val - minVal) / range))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: geo.size.height))
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [.red.opacity(0.15), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - History Sheet

struct HistorySheet: View {
    let readings: [HealthKitManager.HeartRateReading]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(readings) { reading in
                    HStack {
                        Circle()
                            .fill(reading.zone.color)
                            .frame(width: 8, height: 8)
                        Text("\(Int(reading.bpm))")
                            .font(.system(.title3, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let source = reading.source {
                                Text(source)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ContentView()
}
