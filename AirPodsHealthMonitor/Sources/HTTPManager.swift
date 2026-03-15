import Foundation

/// Posts heart-rate data to an HTTP endpoint. Settings are persisted in UserDefaults.
@MainActor
final class HTTPManager: ObservableObject {

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "http_enabled")
        }
    }
    @Published var endpointURL: String {
        didSet { UserDefaults.standard.set(endpointURL, forKey: "http_url") }
    }
    @Published var bearerToken: String {
        didSet { UserDefaults.standard.set(bearerToken, forKey: "http_bearer") }
    }
    @Published var lastPublished: Date?
    @Published var messageCount: Int = 0
    @Published var lastError: String?

    private let session = URLSession.shared

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "http_enabled")
        endpointURL = defaults.string(forKey: "http_url") ?? ""
        bearerToken = defaults.string(forKey: "http_bearer") ?? ""
    }

    func publishHeartRate(_ bpm: Double, source: String?, timestamp: Date) {
        guard isEnabled, let url = URL(string: endpointURL), !endpointURL.isEmpty else { return }

        let payload: [String: Any] = [
            "bpm": round(bpm * 10) / 10,
            "source": source ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "device": "AirPodsHealthMonitor"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        Task {
            do {
                let (_, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(status) {
                    lastPublished = Date()
                    messageCount += 1
                    lastError = nil
                } else {
                    lastError = "HTTP \(status)"
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
