import Foundation

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
        await runAllNow()
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

    func importMonitors(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            var imported = try await store.importMonitors(from: data)
            let existingIDs = Set(monitors.map(\.id))
            for index in imported.indices where existingIDs.contains(imported[index].id) {
                imported[index].id = UUID()
                imported[index].state = .init()
            }
            monitors.append(contentsOf: imported)
            if selectedMonitorID == nil {
                selectedMonitorID = monitors.first?.id
            }
            await persistNow()
            await synchronizeEngine()
        } catch {
            transientMessage = error.localizedDescription
        }
    }
}
