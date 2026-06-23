# AirPods Health Monitor

An iOS app that fetches and displays real-time heart rate data from **AirPods Pro 3** (and other Apple health sources) using HealthKit.

## Features

- **Real-time heart rate** — live BPM from AirPods Pro 3 or any connected source
- **Circular HR gauge** — animated ring showing BPM within max heart rate
- **Pulsing heart animation** — beats at your actual measured BPM with glow effects
- **Heart rate zones** — Rest, Fat Burn, Cardio, Peak, Extreme with color coding
- **Live statistics** — min, max, and average across your session
- **HRV (Heart Rate Variability)** — RMSSD calculated from recent readings
- **Trend indicator** — shows if HR is rising, falling, or stable
- **Time in zones** — stacked bar chart of zone distribution
- **Live ECG waveform** — synthetic PQRST trace scrolling at your BPM
- **Sparkline chart** — visual trend of your last 30 readings
- **Session timer** — tracks how long you've been monitoring
- **Reading history** — scrollable sheet of all captured readings with timestamps
- **Haptic feedback** — subtle taps synced to each heartbeat
- **AirPods detection** — automatically highlights AirPods Pro 3 as the data source

## How it works

AirPods Pro 3 uses its built-in optical sensor to measure heart rate, surfacing the data through Apple's **HealthKit** framework — the same pipeline used by Apple Watch. This app:

1. Requests HealthKit authorization for `HKQuantityTypeIdentifierHeartRate`
2. Runs a live `HKAnchoredObjectQuery` that wakes up on every new sample
3. Prefers samples whose source name contains "AirPods"; falls back to the most recent reading from any source
4. Tracks readings over time to compute stats and render a sparkline
5. Classifies each reading into a heart rate zone

## Project Setup (Xcode)

1. Open Xcode → **File → New → Project** → iOS App
2. Set **Product Name** to `AirPodsHealthMonitor`
3. Set **Interface** to SwiftUI, **Language** to Swift
4. Replace the generated files with the files in `AirPodsHealthMonitor/Sources/`:
   - `AirPodsHealthApp.swift`
   - `ContentView.swift`
   - `HealthKitManager.swift`
   - `HapticManager.swift`
5. In the **Signing & Capabilities** tab, add the **HealthKit** capability
6. In your `Info.plist`, add `NSHealthShareUsageDescription` (see `Resources/Info.plist`)
7. Build and run on a real iPhone (HealthKit is not available in the Simulator)

## Requirements

| Requirement | Details |
|---|---|
| Platform | iOS 17+ |
| Device | Real iPhone (HealthKit unsupported in Simulator) |
| AirPods | AirPods Pro 3 (or any AirPods model with heart rate) paired and connected |
| Xcode | 16+ |

## Key files

| File | Purpose |
|---|---|
| `HealthKitManager.swift` | Authorization, live query, history, stats, zone classification |
| `ContentView.swift` | SwiftUI UI — heart, sparkline, zones, stats, history sheet |
| `HapticManager.swift` | Haptic feedback for heartbeats and zone changes |
| `AirPodsHealthApp.swift` | App entry point |
| `Resources/Info.plist` | HealthKit permission strings & capabilities |

## Heart Rate Zones

| Zone | BPM Range | Color |
|---|---|---|
| Rest | < 100 | Blue |
| Fat Burn | 100–139 | Green |
| Cardio | 140–169 | Yellow |
| Peak | 170–199 | Orange |
| Extreme | 200+ | Red |

## Notes

- The app distinguishes AirPods data from Apple Watch or iPhone data by inspecting `HKSourceRevision.source.name`.
- Heart rate is only recorded when your AirPods Pro 3 are in your ears and you are relatively still.
- Background updates require enabling **Background Modes → Background Processing** capability and using `HKObserverQuery` with `enableBackgroundDelivery`.
