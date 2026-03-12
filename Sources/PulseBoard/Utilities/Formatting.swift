import Foundation
import SwiftUI
import UserNotifications

enum PulseFormatters {
    static func time(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 1_000 {
            return String(format: "%.2fs", value / 1_000)
        }
        return String(format: "%.0fms", value)
    }

    static func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    static func daysUntil(_ date: Date?) -> String {
        guard let date else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return "\(max(days, 0))d"
    }

    static func statusCode(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    static func notificationStatus(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Authorized"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    static func uptime(for checks: [MonitorCheck]) -> Double? {
        let recent = checks.filter { $0.checkedAt >= Date().addingTimeInterval(-86_400) }
        guard !recent.isEmpty else { return nil }
        let successful = recent.filter { $0.resultingStatus == .up }.count
        return Double(successful) / Double(recent.count) * 100
    }

    static func averageLatency(for checks: [MonitorCheck]) -> Double? {
        let values = checks.compactMap(\.responseTimeMs)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

extension Collection where Element == MonitorCheck {
    func recent(limit: Int) -> [MonitorCheck] {
        sorted { $0.checkedAt > $1.checkedAt }.prefix(limit).map { $0 }
    }
}

extension MonitorStatus {
    var tint: Color {
        switch self {
        case .up:
            return Color(red: 0.28, green: 0.78, blue: 0.43)
        case .degraded:
            return Color(red: 0.95, green: 0.72, blue: 0.23)
        case .down:
            return Color(red: 0.95, green: 0.30, blue: 0.33)
        case .unknown:
            return Color.white.opacity(0.55)
        }
    }

    var label: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .up:
            return "checkmark.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .down:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

extension MonitorKind {
    var symbolName: String {
        switch self {
        case .http:
            return "globe"
        case .keyword:
            return "text.magnifyingglass"
        case .tcp:
            return "cable.connector"
        case .dns:
            return "network"
        }
    }
}

extension IncidentType {
    var tint: Color {
        switch self {
        case .failure:
            return MonitorStatus.down.tint
        case .recovery:
            return MonitorStatus.up.tint
        case .warning:
            return MonitorStatus.degraded.tint
        }
    }
}
