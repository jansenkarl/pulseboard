import Foundation

actor MonitoringEngine {
    private let checker: MonitorCheckService
    private let onResult: @Sendable (UUID, MonitorCheck) async -> Void
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var inFlight: Set<UUID> = []

    init(checker: MonitorCheckService, onResult: @escaping @Sendable (UUID, MonitorCheck) async -> Void) {
        self.checker = checker
        self.onResult = onResult
    }

    func configure(monitors: [Monitor], pauseAll: Bool) {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        guard !pauseAll else { return }

        for monitor in monitors where monitor.isEnabled {
            tasks[monitor.id] = Task(priority: .background) { [checker, onResult] in
                while !Task.isCancelled {
                    let check = await checker.performCheck(for: monitor)
                    await onResult(monitor.id, check)

                    do {
                        try await Task.sleep(for: .seconds(monitor.interval))
                    } catch {
                        break
                    }
                }
            }
        }
    }

    func runNow(_ monitor: Monitor) {
        Task(priority: .userInitiated) {
            _ = await runNowSynchronously(monitor)
        }
    }

    func runAllNow(monitors: [Monitor]) async -> Int {
        var checksStarted = 0
        for monitor in monitors where monitor.isEnabled {
            let didRun = await runNowSynchronously(monitor)
            if didRun {
                checksStarted += 1
            }
        }
        return checksStarted
    }

    private func runNowSynchronously(_ monitor: Monitor) async -> Bool {
        guard !inFlight.contains(monitor.id) else { return false }
        inFlight.insert(monitor.id)
        let check = await checker.performCheck(for: monitor)
        await onResult(monitor.id, check)
        finishRun(for: monitor.id)
        return true
    }

    private func finishRun(for monitorID: UUID) {
        inFlight.remove(monitorID)
    }
}
