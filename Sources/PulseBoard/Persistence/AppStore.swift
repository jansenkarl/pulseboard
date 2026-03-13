import Foundation

struct ConfigurationTransferPayload: Codable, Sendable {
    var schemaVersion: Int = 1
    var monitors: [Monitor]
    var settings: AppSettings
}

struct ImportedConfiguration: Sendable {
    var monitors: [Monitor]
    var settings: AppSettings?
}

actor AppStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
    }

    func load() throws -> AppDocumentState {
        let stateURL = try Self.stateFileURL()
        // Use path(percentEncoded: false) for FileManager/print so that
        // spaces in the path (e.g. "Application Support") are not shown as
        // %20.  The old URL.path() method defaults to percentEncoded:true on
        // macOS 13+ which would cause fileExists(atPath:) to look for a file
        // literally named "Application%20Support" — and always fail.
        let decodedPath = stateURL.path(percentEncoded: false)
        print("[PulseBoard] AppStore.load: path=\(decodedPath)")
        do {
            let data = try Data(contentsOf: stateURL)
            let result = try decoder.decode(AppDocumentState.self, from: data)
            print("[PulseBoard] AppStore.load: decoded smtp.host='\(result.settings.smtp.host)'")
            return result
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            print("[PulseBoard] AppStore.load: file absent — returning seeded state")
            return .seeded
        }
    }

    func save(_ state: AppDocumentState) throws {
        let pruned = prune(state)
        let stateURL = try Self.stateFileURL()
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        print("[PulseBoard] AppStore.save: writing smtp.host='\(pruned.settings.smtp.host)' → \(stateURL.path(percentEncoded: false))")
        let data = try encoder.encode(pruned)
        try data.write(to: stateURL, options: .atomic)
    }

    /// Synchronous, nonisolated save for use from `applicationWillTerminate`
    /// (runs on the calling thread without needing an actor hop).
    nonisolated func saveForTermination(_ state: AppDocumentState) {
        guard let stateURL = try? Self.stateFileURL() else { return }
        let pruned = Self.pruneStatic(state)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        enc.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        guard let data = try? enc.encode(pruned) else { return }
        print("[PulseBoard] AppStore.saveForTermination: smtp.host='\(pruned.settings.smtp.host)' → \(stateURL.path(percentEncoded: false))")
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: stateURL, options: .atomic)
    }

    func exportData(for state: AppDocumentState) throws -> Data {
        try encoder.encode(configurationPayload(for: state))
    }

    func importConfiguration(from data: Data) throws -> ImportedConfiguration {
        if let payload = try? decoder.decode(ConfigurationTransferPayload.self, from: data) {
            return ImportedConfiguration(monitors: payload.monitors, settings: payload.settings)
        }

        // Backward compatibility: previous exports used full document state.
        if let payload = try? decoder.decode(AppDocumentState.self, from: data) {
            return ImportedConfiguration(monitors: payload.monitors, settings: payload.settings)
        }

        // Backward compatibility: plain monitor arrays are still supported.
        if let monitors = try? decoder.decode([Monitor].self, from: data) {
            return ImportedConfiguration(monitors: monitors, settings: nil)
        }

        struct WrappedMonitors: Decodable {
            let monitors: [Monitor]
        }
        let wrapped = try decoder.decode(WrappedMonitors.self, from: data)
        return ImportedConfiguration(monitors: wrapped.monitors, settings: nil)
    }

    func importMonitors(from data: Data) throws -> [Monitor] {
        try importConfiguration(from: data).monitors
    }

    private func prune(_ state: AppDocumentState) -> AppDocumentState {
        Self.pruneStatic(state)
    }

    private func configurationPayload(for state: AppDocumentState) -> ConfigurationTransferPayload {
        ConfigurationTransferPayload(
            monitors: state.monitors.map(Self.sanitizedMonitorForConfiguration),
            settings: Self.sanitizedSettingsForConfiguration(state.settings)
        )
    }

    private static func sanitizedSettingsForConfiguration(_ settings: AppSettings) -> AppSettings {
        var sanitized = settings
        sanitized.smtp.passwordReference = nil
        sanitized.sms.authTokenReference = nil
        return sanitized
    }

    private static func sanitizedMonitorForConfiguration(_ monitor: Monitor) -> Monitor {
        var sanitized = monitor
        sanitized.state = .init()
        sanitized.bearerTokenReference = nil
        return sanitized
    }

    /// Static (nonisolated-safe) version of prune used by saveForTermination.
    private static func pruneStatic(_ state: AppDocumentState) -> AppDocumentState {
        let retentionCutoff = Calendar.current.date(byAdding: .day, value: -state.settings.monitoring.retentionDays, to: Date()) ?? .distantPast
        let prunedChecks = state.checksByMonitor.mapValues { checks in
            checks
                .filter { $0.checkedAt >= retentionCutoff }
                .sorted { $0.checkedAt > $1.checkedAt }
                .prefix(400)
                .map { $0 }
        }
        let prunedIncidents = state.incidents
            .filter { $0.timestamp >= retentionCutoff }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(500)
            .map { $0 }
        return AppDocumentState(
            monitors: state.monitors,
            incidents: prunedIncidents,
            checksByMonitor: prunedChecks,
            settings: state.settings
        )
    }

    private static func appSupportDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return baseURL.appending(path: "PulseBoard", directoryHint: .isDirectory)
    }

    private static func stateFileURL() throws -> URL {
        try appSupportDirectory().appending(path: "state.json", directoryHint: .notDirectory)
    }
}
