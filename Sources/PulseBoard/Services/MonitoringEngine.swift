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
        guard !inFlight.contains(monitor.id) else { return }
        inFlight.insert(monitor.id)

        Task(priority: .userInitiated) { [checker, onResult] in
            let check = await checker.performCheck(for: monitor)
            await onResult(monitor.id, check)
            self.finishRun(for: monitor.id)
        }
    }

    func runAllNow(monitors: [Monitor], pauseAll: Bool) {
        guard !pauseAll else { return }
        for monitor in monitors where monitor.isEnabled {
            runNow(monitor)
        }
    }

    private func finishRun(for monitorID: UUID) {
        inFlight.remove(monitorID)
    }
}
