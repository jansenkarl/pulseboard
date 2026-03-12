import Foundation
import ServiceManagement

extension AppModel {

    // MARK: - Settings draft

    /// Returns a fully-populated `SettingsDraft` with Keychain fields loaded so
    /// that SecureFields show dots rather than appearing blank after a previous apply.
    func settingsDraft() async -> SettingsDraft {
        var draft = SettingsDraft(settings: settings)
        if let ref = settings.smtp.passwordReference {
            draft.smtpPassword = (try? await keychain.readSecret(for: ref)) ?? ""
        }
        if let ref = settings.sms.authTokenReference {
            draft.smsAuthToken = (try? await keychain.readSecret(for: ref)) ?? ""
        }
        return draft
    }

    // MARK: - Apply settings

    @discardableResult
    func applySettings(_ draft: SettingsDraft) async -> Bool {
        do {
            var newSettings = draft.settings
            newSettings.smtp.toAddresses       = splitCSV(draft.smtpToAddressesText)
            newSettings.sms.recipientNumbers   = splitCSV(draft.smsRecipientsText)
            newSettings.localAlerts.route  = buildRoute(mode: draft.localAlertRouteMode,  monitorIDs: draft.localRouteMonitorIDs,  tagsText: draft.localRouteTagsText)
            newSettings.emailAlerts.route  = buildRoute(mode: draft.emailAlertRouteMode,  monitorIDs: draft.emailRouteMonitorIDs,  tagsText: draft.emailRouteTagsText)
            newSettings.smsAlerts.route    = buildRoute(mode: draft.smsAlertRouteMode,    monitorIDs: draft.smsRouteMonitorIDs,    tagsText: draft.smsRouteTagsText)
            newSettings.monitoring.defaultInterval  = max(15, newSettings.monitoring.defaultInterval)
            newSettings.monitoring.defaultTimeout   = max(2,  newSettings.monitoring.defaultTimeout)
            newSettings.monitoring.retryCount       = max(1,  newSettings.monitoring.retryCount)
            newSettings.monitoring.cooldownInterval = max(60, newSettings.monitoring.cooldownInterval)
            newSettings.monitoring.retentionDays    = max(1,  newSettings.monitoring.retentionDays)

            // Keychain saves are non-fatal: a failure (e.g. unsigned binary /
            // access denied) should not abort saving all the other settings.
            var keychainError: String?

            if !draft.smtpPassword.isEmpty {
                let reference = newSettings.smtp.passwordReference ?? "smtp.password"
                do {
                    try await keychain.save(secret: draft.smtpPassword, for: reference)
                    newSettings.smtp.passwordReference = reference
                } catch {
                    keychainError = "SMTP password could not be saved to Keychain: \(error.localizedDescription)"
                }
            }

            if !draft.smsAuthToken.isEmpty {
                let reference = newSettings.sms.authTokenReference ?? "sms.token"
                do {
                    try await keychain.save(secret: draft.smsAuthToken, for: reference)
                    newSettings.sms.authTokenReference = reference
                } catch {
                    let msg = "SMS token could not be saved to Keychain: \(error.localizedDescription)"
                    keychainError = keychainError.map { $0 + "\n" + msg } ?? msg
                }
            }

            let previousLaunchAtLogin = settings.launchAtLogin
            var launchAtLoginErrorMessage: String?
            if previousLaunchAtLogin != newSettings.launchAtLogin {
                do {
                    try await updateLaunchAtLogin(enabled: newSettings.launchAtLogin)
                } catch {
                    launchAtLoginErrorMessage = error.localizedDescription
                    newSettings.launchAtLogin = previousLaunchAtLogin
                }
            }

            settings = newSettings
            print("[PulseBoard] applySettings: calling persistNow() — smtp.host='\(newSettings.smtp.host)'")
            let didPersist = await persistNow()
            print("[PulseBoard] applySettings: persistNow returned \(didPersist)")
            guard didPersist else { return false }
            await synchronizeEngine()
            await refreshNotificationStatus()

            let warnings = [keychainError, launchAtLoginErrorMessage].compactMap { $0 }
            if !warnings.isEmpty {
                transientMessage = warnings.joined(separator: "\n")
            }

            print("[PulseBoard] applySettings: SUCCESS — returning true")
            return true
        } catch {
            print("[PulseBoard] applySettings: outer catch — \(error)")
            transientMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Test alert

    func sendTestAlert(_ channel: AlertChannelKind, using draft: SettingsDraft? = nil) async {
        do {
            if let draft {
                let didApplySettings = await applySettings(draft)
                guard didApplySettings else { return }
            }
            try await alerting.sendTestAlert(channel: channel, settings: settings)
            transientMessage = "Test alert sent."
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    // MARK: - Private helpers

    private func buildRoute(
        mode: SettingsDraft.RouteMode,
        monitorIDs: Set<UUID>,
        tagsText: String
    ) -> AlertRoute {
        switch mode {
        case .all:
            return AlertRoute(appliesToAllMonitors: true,  monitorIDs: [],                   tags: [])
        case .monitors:
            return AlertRoute(appliesToAllMonitors: false, monitorIDs: Array(monitorIDs),    tags: [])
        case .tags:
            return AlertRoute(appliesToAllMonitors: false, monitorIDs: [],                   tags: splitCSV(tagsText))
        }
    }

    func refreshLaunchAtLoginState() async {
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLogin(enabled: Bool) async throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            throw SettingsValidationError("Launch at login could not be updated in this environment.")
        }
    }
}

// MARK: - Validation

private struct SettingsValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
