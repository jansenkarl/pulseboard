import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Navigation

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard
    case monitors
    case incidents
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .monitors:  return "Monitors"
        case .incidents: return "Incidents"
        case .settings:  return "Settings"
        case .help:      return "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .monitors:  return "list.bullet.rectangle.portrait.fill"
        case .incidents: return "timeline.selection"
        case .settings:  return "gearshape.fill"
        case .help:      return "questionmark.circle.fill"
        }
    }
}

// MARK: - AppModel

@MainActor
final class AppModel: ObservableObject {

    // MARK: Published state

    @Published var monitors: [Monitor] = []
    @Published var incidents: [Incident] = []
    @Published var checksByMonitor: [UUID: [MonitorCheck]] = [:]
    @Published var settings: AppSettings = .init()
    @Published var selectedSection: SidebarSection = .dashboard
    @Published var selectedMonitorID: UUID?
    @Published var searchText = ""
    @Published var selectedTag = "All"
    @Published var isShowingMonitorEditor = false
    @Published var monitorDraft = MonitorDraft()
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var transientMessage: String?

    // MARK: Services
    // Internal (not private) so AppModel extension files in other sources can reach them.

    let store = AppStore()
    let keychain = KeychainStore()
    let localNotifications = LocalNotificationService()
    let smtpClient = SMTPClient()
    let smsClient = SMSClient()
    lazy var checker = MonitorCheckService(keychain: keychain)
    lazy var alerting = AlertingService(
        localNotifications: localNotifications,
        smtpClient: smtpClient,
        smsClient: smsClient,
        keychain: keychain
    )
    lazy var engine = MonitoringEngine(checker: checker) { [weak self] monitorID, check in
        await self?.handleCheckResult(monitorID: monitorID, check: check)
    }
    var saveTask: Task<Void, Never>?

    // MARK: Init

    init() {
        Task { await bootstrap() }
    }

    // MARK: Monitor queries

    func monitor(for id: UUID?) -> Monitor? {
        guard let id else { return nil }
        return monitors.first { $0.id == id }
    }

    func checks(for monitorID: UUID) -> [MonitorCheck] {
        checksByMonitor[monitorID, default: []].sorted { $0.checkedAt > $1.checkedAt }
    }

    func uptime24h(for monitorID: UUID) -> Double? {
        PulseFormatters.uptime(for: checks(for: monitorID))
    }

    func averageLatency(for monitorID: UUID) -> Double? {
        PulseFormatters.averageLatency(for: checks(for: monitorID))
    }

    // MARK: Engine & notification actions

    func runAllNow() async {
        await engine.runAllNow(monitors: monitors, pauseAll: settings.pauseAllMonitoring)
    }

    func runMonitorNow(_ monitor: Monitor) async {
        await engine.runNow(monitor)
    }

    func requestNotificationPermission() async {
        do {
            let currentStatus = await alerting.notificationStatus()
            switch currentStatus {
            case .notDetermined:
                let updatedStatus = try await alerting.requestNotificationPermission()
                notificationAuthorizationStatus = updatedStatus
                transientMessage = isNotificationAuthorized(updatedStatus)
                    ? "Notification permission granted."
                    : notificationPermissionGuidance(for: updatedStatus)
            case .denied:
                notificationAuthorizationStatus = currentStatus
                transientMessage = notificationPermissionGuidance(for: currentStatus)
            case .authorized, .provisional, .ephemeral:
                notificationAuthorizationStatus = currentStatus
                transientMessage = "Notification permission is already authorized."
            @unknown default:
                notificationAuthorizationStatus = currentStatus
                transientMessage = "Notification permission is in an unknown state."
            }
        } catch {
            await refreshNotificationStatus()
            transientMessage = error.localizedDescription
        }
    }

    func refreshNotificationStatus() async {
        notificationAuthorizationStatus = await alerting.notificationStatus()
    }

    var canSendLocalNotificationTest: Bool {
        notificationAuthorizationStatus != .denied
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    func isNotificationAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    func notificationPermissionGuidance(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Notifications are denied for PulseBoard. Enable them in System Settings → Notifications."
        case .notDetermined:
            return "Notification permission has not been granted yet. Click Request Permission to allow alerts."
        case .authorized, .provisional, .ephemeral:
            return "Notifications are authorized."
        @unknown default:
            return "Notification permission is in an unknown state."
        }
    }

    // MARK: Persistence flush (public surface)

    func flushPersistence() async {
        _ = await persistNow()
    }

    /// Synchronous best-effort save called from `applicationWillTerminate`.
    /// Must be called on the main thread (which `applicationWillTerminate` guarantees).
    func terminationFlush() {
        let snapshot = currentStateSnapshot()
        store.saveForTermination(snapshot)
    }

    // MARK: Shared helpers

    /// CSV / newline-separated text parser shared by MonitorEditor and Settings extensions.
    func splitCSV(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
