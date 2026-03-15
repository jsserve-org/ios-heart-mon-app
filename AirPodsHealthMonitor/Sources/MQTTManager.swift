import Foundation
@preconcurrency import CocoaMQTT

/// Publishes heart-rate data over MQTT. Settings are persisted in UserDefaults.
@MainActor
final class MQTTManager: NSObject, ObservableObject, @preconcurrency CocoaMQTTDelegate {

    @Published var isConnected = false
    @Published var brokerHost: String {
        didSet { UserDefaults.standard.set(brokerHost, forKey: "mqtt_host") }
    }
    @Published var brokerPort: String {
        didSet { UserDefaults.standard.set(brokerPort, forKey: "mqtt_port") }
    }
    @Published var topic: String {
        didSet { UserDefaults.standard.set(topic, forKey: "mqtt_topic") }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "mqtt_username") }
    }
    @Published var password: String {
        didSet { UserDefaults.standard.set(password, forKey: "mqtt_password") }
    }
    @Published var clientName: String {
        didSet { UserDefaults.standard.set(clientName, forKey: "mqtt_client_name") }
    }
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "mqtt_enabled")
            if isEnabled { connect() } else { disconnect() }
        }
    }
    @Published var lastPublished: Date?
    @Published var messageCount: Int = 0

    private var mqtt: CocoaMQTT?

    override init() {
        let defaults = UserDefaults.standard
        brokerHost = defaults.string(forKey: "mqtt_host") ?? "broker.emqx.io"
        brokerPort = defaults.string(forKey: "mqtt_port") ?? "1883"
        topic = defaults.string(forKey: "mqtt_topic") ?? "airpods/heartrate"
        username = defaults.string(forKey: "mqtt_username") ?? ""
        password = defaults.string(forKey: "mqtt_password") ?? ""
        clientName = defaults.string(forKey: "mqtt_client_name") ?? "AirPodsMon"
        isEnabled = defaults.bool(forKey: "mqtt_enabled")
        super.init()
        if isEnabled { connect() }
    }

    func connect() {
        mqtt?.disconnect()
        let port = UInt16(brokerPort) ?? 1883
        let prefix = clientName.isEmpty ? "AirPodsMon" : clientName
        let clientID = "\(prefix)-\(UUID().uuidString.prefix(8))"
        let client = CocoaMQTT(clientID: clientID, host: brokerHost, port: port)
        if !username.isEmpty {
            client.username = username
            client.password = password
        }
        client.delegate = self
        client.keepAlive = 60
        client.autoReconnect = true
        client.autoReconnectTimeInterval = 3
        _ = client.connect()
        mqtt = client
    }

    func disconnect() {
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
        isConnected = false
    }

    func publishHeartRate(_ bpm: Double, source: String?, timestamp: Date) {
        guard isEnabled, isConnected, let mqtt else { return }
        let payload: [String: Any] = [
            "bpm": round(bpm * 10) / 10,
            "source": source ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "device": "AirPodsHealthMonitor"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        mqtt.publish(topic, withString: json, qos: .qos0)
        lastPublished = Date()
        messageCount += 1
    }

    // MARK: - CocoaMQTTDelegate

    nonisolated func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        let connected = (ack == .accept)
        Task { @MainActor in self.isConnected = connected }
    }

    nonisolated func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: (any Error)?) {
        Task { @MainActor in self.isConnected = false }
    }

    nonisolated func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {}
    nonisolated func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    nonisolated func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    nonisolated func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {}
    nonisolated func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    nonisolated func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    nonisolated func mqttDidPing(_ mqtt: CocoaMQTT) {}
    nonisolated func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
