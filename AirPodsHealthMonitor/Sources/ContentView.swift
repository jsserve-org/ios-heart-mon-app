import SwiftUI

struct ContentView: View {
    @StateObject private var hkManager = HealthKitManager()
    @State private var showHistory = false
    @State private var sessionElapsed: TimeInterval = 0
    @State private var sessionTimer: Timer?

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
                    metricsPanel
                    zoneBreakdownChart
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
        .onAppear { startSessionTimer() }
        .onDisappear { sessionTimer?.invalidate() }
        .alert("Error", isPresented: Binding(
            get: { hkManager.errorMessage != nil },
            set: { if !$0 { hkManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { hkManager.errorMessage = nil }
        } message: {
            Text(hkManager.errorMessage ?? "")
        }
    }

    // MARK: - Session Timer

    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                sessionElapsed = hkManager.sessionDuration
            }
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
                if hkManager.sessionStart != nil {
                    Text(formatDuration(sessionElapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                }
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
            if let bpm = hkManager.heartRate {
                // Circular gauge with BPM inside
                ZStack {
                    CircularHRGauge(value: bpm, max: hkManager.maxHR, color: zoneColor(for: bpm))
                        .frame(width: 180, height: 180)

                    VStack(spacing: 2) {
                        Text("\(Int(bpm))")
                            .font(.system(size: 56, weight: .thin, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.4), value: bpm)
                        Text("BPM")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(2)
                    }

                    // Trend arrow at top of gauge
                    HStack(spacing: 4) {
                        Image(systemName: hkManager.trend.icon)
                            .font(.caption2)
                        Text(hkManager.trend.rawValue)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(hkManager.trend.color)
                    .offset(y: -105)
                }

                ECGWaveformView(bpm: bpm)
                    .frame(height: 60)
                    .padding(.horizontal, 20)

                SparklineChart(values: hkManager.history.prefix(30).map(\.bpm).reversed())
                    .frame(height: 40)
                    .padding(.horizontal, 48)
                    .opacity(0.7)
            } else {
                EnhancedPulsingHeart(bpm: nil)
                placeholderBPM
            }
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

    // MARK: - Metrics Panel

    private var metricsPanel: some View {
        Group {
            if let stats = hkManager.stats, stats.count > 1 {
                VStack(spacing: 10) {
                    // Top row: Min / Avg / Max
                    HStack(spacing: 12) {
                        statCard(label: "Min", value: "\(Int(stats.min))", color: .blue)
                        statCard(label: "Avg", value: "\(Int(stats.average))", color: .white)
                        statCard(label: "Max", value: "\(Int(stats.max))", color: .red)
                    }

                    // Bottom row: HRV / Readings / Session
                    HStack(spacing: 12) {
                        if let hrv = hkManager.hrv {
                            metricTile(
                                icon: "waveform.path.ecg",
                                label: "HRV",
                                value: String(format: "%.0f ms", hrv),
                                color: hrvColor(hrv)
                            )
                        }
                        metricTile(
                            icon: "number",
                            label: "Readings",
                            value: "\(hkManager.history.count)",
                            color: .white.opacity(0.6)
                        )
                        if sessionElapsed > 0 {
                            metricTile(
                                icon: "timer",
                                label: "Session",
                                value: formatDuration(sessionElapsed),
                                color: .white.opacity(0.6)
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
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
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color.opacity(0.6))
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Zone Breakdown

    private var zoneBreakdownChart: some View {
        Group {
            if !hkManager.zoneBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time in Zones")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .textCase(.uppercase)
                        .tracking(1)

                    HStack(spacing: 3) {
                        ForEach(hkManager.zoneBreakdown) { entry in
                            let fraction = Double(entry.count) / Double(hkManager.history.count)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.zone.color)
                                .frame(maxWidth: .infinity)
                                .frame(height: 8)
                                .opacity(max(fraction, 0.05))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                .layoutPriority(fraction)
                        }
                    }
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    HStack(spacing: 12) {
                        ForEach(hkManager.zoneBreakdown) { entry in
                            let pct = Int(Double(entry.count) / Double(hkManager.history.count) * 100)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(entry.zone.color)
                                    .frame(width: 6, height: 6)
                                Text("\(entry.zone.rawValue) \(pct)%")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
        }
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

    // MARK: - Helpers

    private func zoneColor(for bpm: Double) -> Color {
        HealthKitManager.HeartRateZone.from(bpm: bpm).color
    }

    private func hrvColor(_ hrv: Double) -> Color {
        switch hrv {
        case ..<20: return .red
        case 20..<50: return .orange
        case 50..<100: return .green
        default: return .blue
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Circular HR Gauge

struct CircularHRGauge: View {
    let value: Double
    let max: Double
    let color: Color

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(.white.opacity(0.06), lineWidth: 8)

            // Filled arc
            Circle()
                .trim(from: 0, to: min(value / max, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.3), color, color.opacity(0.6)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * value / max)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Glow
            Circle()
                .trim(from: 0, to: min(value / max, 1.0))
                .stroke(color.opacity(0.2), lineWidth: 16)
                .rotationEffect(.degrees(-90))
                .blur(radius: 6)

            // Tick marks
            ForEach(0..<12) { i in
                let angle = Double(i) * 30.0
                let isMajor = i % 3 == 0
                Rectangle()
                    .fill(.white.opacity(isMajor ? 0.15 : 0.07))
                    .frame(width: 1.5, height: isMajor ? 10 : 6)
                    .offset(y: -80)
                    .rotationEffect(.degrees(angle))
            }
        }
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

// MARK: - ECG Waveform

struct ECGWaveformView: View {
    let bpm: Double
    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Grid lines (hospital monitor style)
                ECGGrid()
                    .stroke(Color.green.opacity(0.06), lineWidth: 0.5)

                // Main trace
                ECGTrace(phase: phase, samplesPerBeat: max(w * 0.4, 80))
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.1),
                                Color.green.opacity(0.5),
                                Color.green,
                                Color.green.opacity(0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                // Glow layer
                ECGTrace(phase: phase, samplesPerBeat: max(w * 0.4, 80))
                    .stroke(Color.green.opacity(0.25), lineWidth: 6)
                    .blur(radius: 4)

                // Leading dot
                let dotX = w * 0.92
                let traceY = ecgY(at: phase, in: h)
                Circle()
                    .fill(Color.green)
                    .frame(width: 4, height: 4)
                    .shadow(color: .green.opacity(0.8), radius: 4)
                    .position(x: dotX, y: traceY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.green.opacity(0.1), lineWidth: 1)
            )
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: bpm) { _, _ in startTimer() }
    }

    private func startTimer() {
        stopTimer()
        guard bpm > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let samplesPerBeat = UIScreen.main.bounds.width * 0.4
            let increment = 1.0 / (samplesPerBeat * CGFloat(bpm / 60.0)) * 60.0
            Task { @MainActor in
                phase += increment
                if phase > 1000 { phase -= 1000 }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func ecgY(at phase: CGFloat, in height: CGFloat) -> CGFloat {
        let t = phase - floor(phase)
        let mid = height * 0.5
        let amp = height * 0.35
        return mid - ecgValue(at: t) * amp
    }
}

struct ECGTrace: Shape {
    var phase: CGFloat
    var samplesPerBeat: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.height * 0.5
        let amp = rect.height * 0.35

        let totalSamples = Int(samplesPerBeat)
        for i in 0...totalSamples {
            let x = rect.width * CGFloat(i) / CGFloat(totalSamples)
            let t = (CGFloat(i) / samplesPerBeat + phase) - floor(CGFloat(i) / samplesPerBeat + phase)
            let y = mid - ecgValue(at: t) * amp

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

struct ECGGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 20
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return path
    }
}

/// Synthetic PQRST waveform — t is 0...1 within one beat cycle
private func ecgValue(at t: CGFloat) -> CGFloat {
    var v: CGFloat = 0
    v += gaussian(t, center: 0.10, width: 0.025, height: 0.12)
    v -= gaussian(t, center: 0.18, width: 0.008, height: 0.08)
    v += gaussian(t, center: 0.20, width: 0.012, height: 1.0)
    v -= gaussian(t, center: 0.23, width: 0.010, height: 0.20)
    v += gaussian(t, center: 0.35, width: 0.035, height: 0.25)
    v += gaussian(t, center: 0.45, width: 0.025, height: 0.04)
    return v
}

private func gaussian(_ t: CGFloat, center: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
    let d = (t - center) / width
    return height * exp(-d * d * 0.5)
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
