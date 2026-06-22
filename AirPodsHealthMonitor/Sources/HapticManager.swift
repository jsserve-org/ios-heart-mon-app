import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let impactFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private init() {
        impactFeedback.prepare()
    }

    func heartbeat() {
        impactFeedback.impactOccurred(intensity: 0.6)
        impactFeedback.prepare()
    }

    func zoneChange() {
        notificationFeedback.notificationOccurred(.warning)
        notificationFeedback.prepare()
    }

    func error() {
        notificationFeedback.notificationOccurred(.error)
        notificationFeedback.prepare()
    }
}
