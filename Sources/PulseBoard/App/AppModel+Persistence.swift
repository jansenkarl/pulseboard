import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {

    // MARK: - Bootstrap

    func bootstrap() async {
        var loadSucceeded = false
        do {
            let state = try await store.load()
            print("[PulseBoard] bootstrap: disk load OK — monitors=\(state.monitors.count) smtp.host='\(state.settings.smtp.host)' smtp.user='\(state.settings.smtp.username)'")
            // Yield before publishing any loaded state.  bootstrap() runs in a
            // Task started from init(), which can wake up while SwiftUI is still
            // computing its first render.  Assigning @Published properties during
            // a render cycle triggers "Publishing changes from within view updates
            // is not allowed" and can silently drop those changes.
            await Task.yield()
            monitors = state.monitors
            incidents = state.incidents.sorted { $0.timestamp > $1.timestamp }
            checksByMonitor = state.checksByMonitor
            settings = state.settings
            selectedMonitorID = monitors.first?.id
            loadSucceeded = true
        } catch {
            print("[PulseBoard] bootstrap: disk load FAILED — \(error)")
            transientMessage = error.localizedDescription
            monitors = Monitor.sampleMonitors
            incidents = []
            checksByMonitor = [:]
            settings = .init()
        }

        await refreshNotificationStatus()
        await refreshLaunchAtLoginState()
        // Only re-persist when load succeeded so that a transient decode error
        // never overwrites good data on disk with in-memory defaults.
        if loadSucceeded {
            let ok = await persistNow()
            print("[PulseBoard] bootstrap: re-persist after load — success=\(ok)")
        }
        await synchronizeEngine()
        if !settings.pauseAllMonitoring {
            _ = await engine.runAllNow(monitors: monitors)
        }
    }

    // MARK: - Engine synchronization

    func synchronizeEngine() async {
        await engine.configure(monitors: monitors, pauseAll: settings.pauseAllMonitoring)
    }

    // MARK: - State snapshot

    func currentStateSnapshot() -> AppDocumentState {
        AppDocumentState(
            monitors: monitors,
            incidents: incidents,
            checksByMonitor: checksByMonitor,
            settings: settings
        )
    }

    // MARK: - Persistence

    func persistSoon() {
        let snapshot = currentStateSnapshot()
        let store = self.store
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            print("[PulseBoard] persistSoon: firing — smtp.host='\(snapshot.settings.smtp.host)' monitors=\(snapshot.monitors.count)")
            try? await store.save(snapshot)
        }
    }

    @discardableResult
    func persistNow() async -> Bool {
        saveTask?.cancel()
        saveTask = nil
        let snapshot = currentStateSnapshot()
        do {
            try await store.save(snapshot)
            print("[PulseBoard] persistNow: SUCCESS — monitors=\(snapshot.monitors.count) smtp.host='\(snapshot.settings.smtp.host)'")
            return true
        } catch {
            print("[PulseBoard] persistNow: FAILED — \(error)")
            transientMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Import / Export

    func exportDocument() async -> ConfigurationDocument {
        let snapshot = currentStateSnapshot()
        do {
            let data = try await store.exportData(for: snapshot)
            return ConfigurationDocument(data: data)
        } catch {
            transientMessage = error.localizedDescription
            return ConfigurationDocument(data: Data())
        }
    }

    func presentExportConfigurationPanel() async {
        do {
            let snapshot = currentStateSnapshot()
            let data = try await store.exportData(for: snapshot)

            let panel = NSSavePanel()
            panel.title = "Export Configuration"
            panel.prompt = "Export"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "PulseBoard-Configuration-\(exportTimestamp()).json"

            guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

            try data.write(to: destinationURL, options: .atomic)
            transientMessage = "Configuration exported successfully."
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    private func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter.string(from: Date())
    }

    func presentImportConfigurationPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Import Configuration"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        await importConfiguration(from: selectedURL)
    }

    // Backward-compatible entry point used by existing callers.
    func presentImportMonitorsPanel() async {
        await presentImportConfigurationPanel()
    }

    func importConfiguration(from url: URL) async {
        do {
            let didAccessSecurityScopedURL = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScopedURL {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let imported = try await store.importConfiguration(from: data)
            let duplicateSummary = duplicateSummary(for: imported)

            let importDecision: ConfigurationImportDecision
            if duplicateSummary.hasAnyDuplicates {
                importDecision = presentDuplicateImportDecision(summary: duplicateSummary)
            } else {
                importDecision = .importAll
            }

            guard importDecision != .cancel else { return }

            let shouldSkipDuplicates = importDecision == .skipDuplicates
            let importedMonitorCandidates = shouldSkipDuplicates ? duplicateSummary.uniqueMonitors : imported.monitors
            let shouldImportSettings: Bool = {
                guard imported.settings != nil else { return false }
                if shouldSkipDuplicates {
                    return !duplicateSummary.hasDuplicateSettings
                }
                return true
            }()

            guard !importedMonitorCandidates.isEmpty || shouldImportSettings else {
                transientMessage = "No new configuration was imported. Everything selected was already present."
                return
            }

            let uniqueIDMonitors = monitorsWithUniqueIDs(
                importedMonitorCandidates,
                existingIDs: Set(monitors.map(\.id))
            )

            if !uniqueIDMonitors.isEmpty {
                monitors.append(contentsOf: uniqueIDMonitors)
                if selectedMonitorID == nil {
                    selectedMonitorID = monitors.first?.id
                }
            }

            var settingsImported = false
            if shouldImportSettings, let importedSettings = imported.settings {
                settings = mergedSettingsForImport(importedSettings)
                settingsImported = true
            }

            let didPersist = await persistNow()
            await synchronizeEngine()
            if didPersist {
                transientMessage = importResultMessage(
                    importedMonitors: uniqueIDMonitors.count,
                    importedSettings: settingsImported,
                    skippedDuplicateMonitors: shouldSkipDuplicates ? duplicateSummary.duplicateMonitors.count : 0,
                    skippedDuplicateSettings: shouldSkipDuplicates && duplicateSummary.hasDuplicateSettings
                )
            }
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    // Backward-compatible entry point used by existing callers.
    func importMonitors(from url: URL) async {
        await importConfiguration(from: url)
    }

    private func mergedSettingsForImport(_ imported: AppSettings) -> AppSettings {
        var merged = imported
        // Imported configuration intentionally excludes secrets. Keep the local
        // keychain references so existing credentials are not lost on this Mac.
        merged.smtp.passwordReference = settings.smtp.passwordReference
        merged.sms.authTokenReference = settings.sms.authTokenReference
        return merged
    }

    private func normalizedSettingsForDuplicateDetection(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        normalized.smtp.passwordReference = nil
        normalized.sms.authTokenReference = nil
        return normalized
    }

    private func duplicateSummary(for imported: ImportedConfiguration) -> ConfigurationDuplicateSummary {
        var existingIDs = Set(monitors.map(\.id))
        var existingSignatures = Set(monitors.map(monitorDuplicateSignature))

        var uniqueMonitors: [Monitor] = []
        var duplicateMonitors: [Monitor] = []

        for monitor in imported.monitors {
            let signature = monitorDuplicateSignature(monitor)
            let isDuplicate = existingIDs.contains(monitor.id) || existingSignatures.contains(signature)
            if isDuplicate {
                duplicateMonitors.append(monitor)
            } else {
                uniqueMonitors.append(monitor)
                existingIDs.insert(monitor.id)
                existingSignatures.insert(signature)
            }
        }

        let hasDuplicateSettings: Bool = {
            guard let importedSettings = imported.settings else { return false }
            return normalizedSettingsForDuplicateDetection(importedSettings) == normalizedSettingsForDuplicateDetection(settings)
        }()

        return ConfigurationDuplicateSummary(
            uniqueMonitors: uniqueMonitors,
            duplicateMonitors: duplicateMonitors,
            hasDuplicateSettings: hasDuplicateSettings
        )
    }

    private func monitorDuplicateSignature(_ monitor: Monitor) -> MonitorDuplicateSignature {
        MonitorDuplicateSignature(
            name: monitor.name,
            kind: monitor.kind,
            target: monitor.target,
            port: monitor.port,
            method: monitor.method,
            expectedStatusCodes: monitor.expectedStatusCodes.sorted(),
            timeout: monitor.timeout,
            interval: monitor.interval,
            tags: monitor.normalizedTags.map { $0.lowercased() }.sorted(),
            keyword: monitor.keyword,
            customHeaders: monitor.customHeaders
                .map { MonitorHeaderSignature(key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .sorted { lhs, rhs in
                    if lhs.key == rhs.key {
                        return lhs.value < rhs.value
                    }
                    return lhs.key < rhs.key
                },
            isEnabled: monitor.isEnabled,
            notifyOnFailure: monitor.notifyOnFailure,
            notifyOnRecovery: monitor.notifyOnRecovery,
            slowThreshold: monitor.slowThreshold,
            sslWarningDays: monitor.sslWarningDays,
            retryCount: monitor.retryCount
        )
    }

    private func monitorsWithUniqueIDs(_ monitors: [Monitor], existingIDs: Set<UUID>) -> [Monitor] {
        var usedIDs = existingIDs
        return monitors.map { monitor in
            var updated = monitor
            while usedIDs.contains(updated.id) {
                updated.id = UUID()
                updated.state = .init()
            }
            usedIDs.insert(updated.id)
            return updated
        }
    }

    private func presentDuplicateImportDecision(summary: ConfigurationDuplicateSummary) -> ConfigurationImportDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Duplicate configuration detected"

        var details: [String] = []
        if !summary.duplicateMonitors.isEmpty {
            details.append("• Duplicate monitors: \(summary.duplicateMonitors.count)")
        }
        if summary.hasDuplicateSettings {
            details.append("• Imported settings match your current settings")
        }
        details.append("Choose “Skip Duplicates” to import only new items, or “Import All” to include duplicates.")
        alert.informativeText = details.joined(separator: "\n")

        alert.addButton(withTitle: "Skip Duplicates")
        alert.addButton(withTitle: "Import All")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .skipDuplicates
        case .alertSecondButtonReturn:
            return .importAll
        default:
            return .cancel
        }
    }

    private func importResultMessage(
        importedMonitors: Int,
        importedSettings: Bool,
        skippedDuplicateMonitors: Int,
        skippedDuplicateSettings: Bool
    ) -> String {
        var parts: [String] = []
        if importedMonitors > 0 {
            let suffix = importedMonitors == 1 ? "" : "s"
            parts.append("Imported \(importedMonitors) monitor\(suffix)")
        }
        if importedSettings {
            parts.append("Imported settings")
        }

        if parts.isEmpty {
            parts.append("No new configuration imported")
        }

        var message = parts.joined(separator: " and ") + "."

        var skipped: [String] = []
        if skippedDuplicateMonitors > 0 {
            let suffix = skippedDuplicateMonitors == 1 ? "" : "s"
            skipped.append("\(skippedDuplicateMonitors) duplicate monitor\(suffix)")
        }
        if skippedDuplicateSettings {
            skipped.append("duplicate settings")
        }
        if !skipped.isEmpty {
            message += " Skipped " + skipped.joined(separator: " and ") + "."
        }

        return message
    }
}

private enum ConfigurationImportDecision {
    case importAll
    case skipDuplicates
    case cancel
}

private struct ConfigurationDuplicateSummary {
    var uniqueMonitors: [Monitor]
    var duplicateMonitors: [Monitor]
    var hasDuplicateSettings: Bool

    var hasAnyDuplicates: Bool {
        !duplicateMonitors.isEmpty || hasDuplicateSettings
    }
}

private struct MonitorHeaderSignature: Hashable {
    var key: String
    var value: String
}

private struct MonitorDuplicateSignature: Hashable {
    var name: String
    var kind: MonitorKind
    var target: String
    var port: Int?
    var method: HTTPMethod
    var expectedStatusCodes: [Int]
    var timeout: TimeInterval
    var interval: TimeInterval
    var tags: [String]
    var keyword: String?
    var customHeaders: [MonitorHeaderSignature]
    var isEnabled: Bool
    var notifyOnFailure: Bool
    var notifyOnRecovery: Bool
    var slowThreshold: TimeInterval?
    var sslWarningDays: Int
    var retryCount: Int
}
