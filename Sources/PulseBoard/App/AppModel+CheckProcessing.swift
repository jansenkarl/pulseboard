import Foundation

extension AppModel {

    // MARK: - Check result ingestion

    func handleCheckResult(monitorID: UUID, check: MonitorCheck) async {
        guard let index = monitors.firstIndex(where: { $0.id == monitorID }) else { return }
        var monitor = monitors[index]
        let previousStatus = monitor.state.currentStatus

        var effectiveStatus = check.resultingStatus
        var effectiveDetail = check.detail
        if check.resultingStatus == .down {
            let failureCount = monitor.state.consecutiveFailures + 1
            monitor.state.consecutiveFailures = failureCount
            if failureCount < max(1, monitor.retryCount) {
                effectiveStatus = .degraded
                effectiveDetail = "Retry \(failureCount) of \(monitor.retryCount) before alerting"
            }
        } else {
            monitor.state.consecutiveFailures = 0
        }

        let storedCheck = MonitorCheck(
            monitorID: check.monitorID,
            checkedAt: check.checkedAt,
            resultingStatus: effectiveStatus,
            responseTimeMs: check.responseTimeMs,
            statusCode: check.statusCode,
            detail: effectiveDetail,
            errorMessage: check.errorMessage,
            matchedKeyword: check.matchedKeyword,
            sslExpiryDate: check.sslExpiryDate,
            resolvedAddresses: check.resolvedAddresses
        )

        monitor.state.currentStatus          = effectiveStatus
        monitor.state.lastCheckedAt          = storedCheck.checkedAt
        monitor.state.lastResponseTimeMs     = storedCheck.responseTimeMs
        monitor.state.lastStatusCode         = storedCheck.statusCode
        monitor.state.lastSSLExpiryDate      = storedCheck.sslExpiryDate
        monitor.state.lastResolvedAddresses  = storedCheck.resolvedAddresses
        monitor.state.lastMessage            = storedCheck.errorMessage ?? storedCheck.detail
        if effectiveStatus != previousStatus {
            monitor.state.lastTransitionAt = storedCheck.checkedAt
        }

        var history = checksByMonitor[monitorID, default: []]
        history.insert(storedCheck, at: 0)
        let newHistory = Array(history.prefix(400))

        // Yield before any @Published mutation to avoid modifying ObservableObject
        // state while SwiftUI is mid-render (causes "Publishing changes from within
        // view updates" undefined-behaviour warning).
        await Task.yield()

        checksByMonitor[monitorID] = newHistory

        let transitionIncident = incidentForTransition(
            previous: previousStatus, current: effectiveStatus,
            monitor: monitor, check: storedCheck
        )
        let repeatedIncident = repeatedIncidentIfNeeded(
            for: monitor, currentStatus: effectiveStatus, at: storedCheck.checkedAt
        )
        let incident = transitionIncident ?? repeatedIncident

        if let incident {
            incidents.insert(incident, at: 0)
            incidents = Array(incidents.prefix(500))

            let shouldAlert = shouldNotify(
                for: monitor, previousStatus: previousStatus,
                currentStatus: effectiveStatus, incident: incident
            )
            if shouldAlert {
                let attempted = await alerting.sendAlert(for: monitor, incident: incident, settings: settings)
                if attempted {
                    monitor.state.lastAlertAt     = incident.timestamp
                    monitor.state.lastAlertStatus = effectiveStatus
                }
            }
        }

        monitors[index] = monitor
        persistSoon()
    }

    // MARK: - Incident creation

    private func incidentForTransition(
        previous: MonitorStatus,
        current: MonitorStatus,
        monitor: Monitor,
        check: MonitorCheck
    ) -> Incident? {
        guard previous != current else { return nil }
        guard !(previous == .unknown && current == .up) else { return nil }

        switch current {
        case .up:
            return Incident(
                monitorID: monitor.id, monitorName: monitor.name,
                type: .recovery, status: .up,
                title: "Recovered",
                message: "The monitor is healthy again.",
                timestamp: check.checkedAt
            )
        case .degraded:
            return Incident(
                monitorID: monitor.id, monitorName: monitor.name,
                type: .warning, status: .degraded,
                title: "Degraded",
                message: check.errorMessage ?? check.detail ?? "The monitor is responding with warnings.",
                timestamp: check.checkedAt
            )
        case .down:
            return Incident(
                monitorID: monitor.id, monitorName: monitor.name,
                type: .failure, status: .down,
                title: "Down",
                message: check.errorMessage ?? check.detail ?? "The monitor failed.",
                timestamp: check.checkedAt
            )
        case .unknown:
            return nil
        }
    }

    private func repeatedIncidentIfNeeded(
        for monitor: Monitor,
        currentStatus: MonitorStatus,
        at timestamp: Date
    ) -> Incident? {
        guard currentStatus == .down || currentStatus == .degraded else { return nil }
        guard
            let lastAlertAt     = monitor.state.lastAlertAt,
            let lastAlertStatus = monitor.state.lastAlertStatus,
            lastAlertStatus == currentStatus,
            timestamp.timeIntervalSince(lastAlertAt) >= settings.monitoring.cooldownInterval
        else { return nil }

        return Incident(
            monitorID: monitor.id, monitorName: monitor.name,
            type: currentStatus == .down ? .failure : .warning,
            status: currentStatus,
            title: currentStatus == .down ? "Still Down" : "Still Degraded",
            message: "The issue is ongoing after the alert cooldown period.",
            timestamp: timestamp
        )
    }

    private func shouldNotify(
        for monitor: Monitor,
        previousStatus: MonitorStatus,
        currentStatus: MonitorStatus,
        incident: Incident
    ) -> Bool {
        switch incident.type {
        case .failure, .warning:
            return monitor.notifyOnFailure &&
                (previousStatus != currentStatus || monitor.state.lastAlertStatus == currentStatus)
        case .recovery:
            return monitor.notifyOnRecovery && previousStatus != .unknown
        }
    }
}
