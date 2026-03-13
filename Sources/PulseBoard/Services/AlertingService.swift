import Foundation
import UserNotifications

actor AlertingService {
    private let localNotifications: LocalNotificationService
    private let smtpClient: SMTPClient
    private let smsClient: SMSClient
    private let keychain: KeychainStore

    init(localNotifications: LocalNotificationService, smtpClient: SMTPClient, smsClient: SMSClient, keychain: KeychainStore) {
        self.localNotifications = localNotifications
        self.smtpClient = smtpClient
        self.smsClient = smsClient
        self.keychain = keychain
    }

    func notificationStatus() async -> UNAuthorizationStatus {
        await localNotifications.authorizationStatus()
    }

    func requestNotificationPermission() async throws -> UNAuthorizationStatus {
        try await localNotifications.requestAuthorization()
    }

    func sendAlert(for monitor: Monitor, incident: Incident, settings: AppSettings) async -> Bool {
        var attempted = false

        if settings.localAlerts.isEnabled, settings.localAlerts.route.matches(monitor: monitor) {
            attempted = true
            try? await localNotifications.send(
                title: incident.title,
                subtitle: monitor.name,
                body: incident.message
            )
        }

        if settings.emailAlerts.isEnabled, settings.emailAlerts.route.matches(monitor: monitor) {
            let password = try? await keychain.readSecret(for: settings.smtp.passwordReference ?? "")
            if settings.smtp.isConfigured {
                attempted = true
                try? await smtpClient.send(
                    subject: "[PulseBoard] \(incident.title)",
                    body: """
                    Monitor: \(monitor.name)
                    Target: \(monitor.displayTarget)
                    Status: \(incident.status.rawValue.uppercased())
                    Time: \(incident.timestamp.formatted(date: .abbreviated, time: .standard))

                    \(incident.message)
                    """,
                    configuration: settings.smtp,
                    password: password ?? nil
                )
            }
        }

        if settings.smsAlerts.isEnabled, settings.smsAlerts.route.matches(monitor: monitor) {
            let token = try? await keychain.readSecret(for: settings.sms.authTokenReference ?? "")
            if settings.sms.isConfigured {
                attempted = true
                try? await smsClient.send(
                    message: "[PulseBoard] \(monitor.name): \(incident.title)",
                    configuration: settings.sms,
                    authToken: token ?? nil
                )
            }
        }

        return attempted
    }

    func sendTestAlert(channel: AlertChannelKind, settings: AppSettings) async throws {
        switch channel {
        case .localNotification:
            try await localNotifications.send(
                title: "PulseBoard Test Alert",
                subtitle: "Local Notifications",
                body: "Notifications are configured and ready."
            )
        case .email:
            let password = try await keychain.readSecret(for: settings.smtp.passwordReference ?? "")
            try await smtpClient.send(
                subject: "[PulseBoard] Test Alert",
                body: "PulseBoard test email sent successfully.",
                configuration: settings.smtp,
                password: password ?? nil
            )
        case .sms:
            let token = try await keychain.readSecret(for: settings.sms.authTokenReference ?? "")
            try await smsClient.send(
                message: "PulseBoard test SMS sent successfully.",
                configuration: settings.sms,
                authToken: token ?? nil
            )
        }
    }
}
