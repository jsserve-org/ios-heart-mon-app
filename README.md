# AirPods Health Monitor

An iOS app that fetches and displays real-time heart rate data from **AirPods Pro 3** (and other Apple health sources) using HealthKit.

## How it works

AirPods Pro 3 uses its built-in optical sensor to measure heart rate, surfacing the data through Apple's **HealthKit** framework — the same pipeline used by Apple Watch. This app:

1. Requests HealthKit authorization for `HKQuantityTypeIdentifierHeartRate`
2. Runs a live `HKAnchoredObjectQuery` that wakes up on every new sample
3. Prefers samples whose source name contains "AirPods"; falls back to the most recent reading from any source
4. Animates the heart icon at the actual measured BPM

## Project Setup (Xcode)

1. Open Xcode → **File → New → Project** → iOS App
2. Set **Product Name** to `AirPodsHealthMonitor`
3. Set **Interface** to SwiftUI, **Language** to Swift
4. Replace the generated files with the files in `Sources/`:
   - `AirPodsHealthApp.swift`
   - `ContentView.swift`
   - `HealthKitManager.swift`
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
| `HealthKitManager.swift` | Authorization, live HKAnchoredObjectQuery, AirPods source detection |
| `ContentView.swift` | SwiftUI UI — pulsing heart, BPM display, source label |
| `AirPodsHealthApp.swift` | App entry point |
| `Resources/Info.plist` | HealthKit permission strings & capabilities |

## Notes

- The app distinguishes AirPods data from Apple Watch or iPhone data by inspecting `HKSourceRevision.source.name`.
- Heart rate is only recorded when your AirPods Pro 3 are in your ears and you are relatively still.
- Background updates require enabling **Background Modes → Background Processing** capability and using `HKObserverQuery` with `enableBackgroundDelivery`.
