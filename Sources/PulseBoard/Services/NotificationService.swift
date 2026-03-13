import Foundation
import UserNotifications

enum LocalNotificationError: LocalizedError {
    case notAuthorized(status: UNAuthorizationStatus)
    case authorizationRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let status):
            switch status {
            case .denied:
                return "Notifications are denied for PulseBoard. Enable notifications in System Settings → Notifications."
            case .notDetermined:
                return "Notification permission has not been requested yet."
            default:
                return "Notifications are not currently authorized."
            }
        case .authorizationRequestFailed(let message):
            return "Unable to request notification permission. \(message)"
        }
    }
}

actor LocalNotificationService {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: LocalNotificationError.authorizationRequestFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: granted)
            }
        }

        return await authorizationStatus()
    }

    func send(title: String, subtitle: String, body: String) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            throw LocalNotificationError.notAuthorized(status: status)
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
