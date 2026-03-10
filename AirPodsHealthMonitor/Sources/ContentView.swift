import SwiftUI

struct ContentView: View {
    @StateObject private var hkManager = HealthKitManager()

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                headerBar
                Spacer()
                heartRateDisplay
                Spacer()
                sourceCard
                Spacer()
                footerTimestamp
                    .padding(.bottom, 40)
            }
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

    // MARK: - Subviews

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                     Color(red: 0.10, green: 0.05, blue: 0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "airpodspro")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
            Text("AirPods Pro 3")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            statusDot
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var statusDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hkManager.heartRate != nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(hkManager.heartRate != nil ? "Live" : "Waiting")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var heartRateDisplay: some View {
        VStack(spacing: 8) {
            // Pulsing heart icon
            PulsingHeart(bpm: hkManager.heartRate)

            if let bpm = hkManager.heartRate {
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(Int(bpm))")
                        .font(.system(size: 96, weight: .thin, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: bpm)
                    Text("BPM")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 14)
                }
            } else {
                placeholderBPM
            }

            Text("Heart Rate")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
                .textCase(.uppercase)
        }
    }

    private var placeholderBPM: some View {
        Group {
            switch hkManager.authorizationStatus {
            case .denied:
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Access Denied")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Open Settings → Privacy → Health\nand allow Heart Rate access.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            case .unavailable:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("HealthKit unavailable")
                        .foregroundStyle(.red)
                }
            default:
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text("Waiting for data…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(height: 140)
    }

    private var sourceCard: some View {
        Group {
            if let source = hkManager.airPodsSource {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Source: \(source)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            } else if hkManager.heartRate != nil {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.yellow)
                    Text("Source: Other device (pair AirPods Pro 3 for direct data)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            }
        }
    }

    private var footerTimestamp: some View {
        Group {
            if let date = hkManager.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
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
            .font(.system(size: 60))
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
