import Foundation

extension AppModel {

    // MARK: - Editor lifecycle

    func openNewMonitor() {
        monitorDraft = MonitorDraft()
        monitorDraft.timeout = settings.monitoring.defaultTimeout
        monitorDraft.interval = settings.monitoring.defaultInterval
        monitorDraft.retryCount = settings.monitoring.retryCount
        isShowingMonitorEditor = true
    }

    func openEditor(for monitor: Monitor) {
        monitorDraft = MonitorDraft(monitor: monitor)
        isShowingMonitorEditor = true
    }

    func dismissMonitorEditor() {
        isShowingMonitorEditor = false
    }

    // MARK: - Save / delete

    func saveMonitor() async {
        do {
            let monitor = try await buildMonitor(from: monitorDraft)
            if let existingIndex = monitors.firstIndex(where: { $0.id == monitor.id }) {
                monitors[existingIndex] = monitor
            } else {
                monitors.append(monitor)
                selectedMonitorID = monitor.id
            }
            isShowingMonitorEditor = false
            await persistNow()
            await synchronizeEngine()
            await engine.runNow(monitor)
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    func deleteSelectedMonitor() async {
        guard let selectedMonitorID else { return }
        monitors.removeAll { $0.id == selectedMonitorID }
        checksByMonitor[selectedMonitorID] = nil
        incidents.removeAll { $0.monitorID == selectedMonitorID }
        self.selectedMonitorID = monitors.first?.id
        await persistNow()
        await synchronizeEngine()
    }

    func setMonitorEnabled(_ monitorID: UUID, isEnabled: Bool) async {
        guard let index = monitors.firstIndex(where: { $0.id == monitorID }) else { return }
        monitors[index].isEnabled = isEnabled
        await persistNow()
        await synchronizeEngine()
    }

    func setPauseAllMonitoring(_ paused: Bool) async {
        settings.pauseAllMonitoring = paused
        await persistNow()
        await synchronizeEngine()
    }

    // MARK: - Monitor builder

    private func buildMonitor(from draft: MonitorDraft) async throws -> Monitor {
        let trimmedName   = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = draft.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty   else { throw MonitorValidationError("Monitor name is required.") }
        guard !trimmedTarget.isEmpty else { throw MonitorValidationError("A URL or host is required.") }

        let id = draft.id ?? UUID()
        let existingMonitor = draft.id.flatMap { existingID in
            monitors.first { $0.id == existingID }
        }

        var tokenReference = existingMonitor?.bearerTokenReference
        if !draft.bearerToken.isEmpty {
            tokenReference = "monitor.\(id.uuidString).bearer"
            try await keychain.save(secret: draft.bearerToken, for: tokenReference!)
        }

        let expectedStatusCodes = splitCSV(draft.expectedStatusCodesText)
            .compactMap(Int.init)
            .filter { (100 ... 599).contains($0) }

        let headers = draft.customHeaders.filter {
            !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let portValue: Int?
        switch draft.kind {
        case .tcp:
            guard let parsedPort = Int(draft.portText), parsedPort > 0, parsedPort <= 65_535 else {
                throw MonitorValidationError("TCP monitors require a valid port number.")
            }
            portValue = parsedPort
        case .http, .keyword, .dns:
            portValue = nil
        }

        var state = existingMonitor?.state ?? .init()
        if draft.id == nil { state.currentStatus = .unknown }

        return Monitor(
            id: id,
            name: trimmedName,
            kind: draft.kind,
            target: trimmedTarget,
            port: portValue,
            method: draft.method,
            expectedStatusCodes: draft.kind == .http || draft.kind == .keyword
                ? (expectedStatusCodes.isEmpty ? [200] : expectedStatusCodes) : [],
            timeout: max(2, draft.timeout),
            interval: max(15, draft.interval),
            tags: splitCSV(draft.tagsText),
            keyword: draft.kind == .keyword
                ? draft.keyword.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
            bearerTokenReference: draft.kind == .http || draft.kind == .keyword
                ? tokenReference : nil,
            customHeaders: draft.kind == .http || draft.kind == .keyword ? headers : [],
            isEnabled: draft.isEnabled,
            notifyOnFailure: draft.notifyOnFailure,
            notifyOnRecovery: draft.notifyOnRecovery,
            slowThreshold: draft.slowThresholdEnabled ? max(0.2, draft.slowThreshold) : nil,
            sslWarningDays: max(1, draft.sslWarningDays),
            retryCount: max(1, draft.retryCount),
            state: state
        )
    }
}

// MARK: - Validation

private struct MonitorValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
