import Foundation

extension AppModel {

    // MARK: - Filtered monitor list

    var filteredMonitors: [Monitor] {
        monitors
            .filter { monitor in
                guard selectedTag != "All" else { return true }
                return monitor.normalizedTags.contains(selectedTag)
            }
            .filter { monitor in
                guard !searchText.isEmpty else { return true }
                let haystack = [
                    monitor.name,
                    monitor.displayTarget,
                    monitor.normalizedTags.joined(separator: " ")
                ].joined(separator: " ").lowercased()
                return haystack.contains(searchText.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.state.currentStatus.priority != rhs.state.currentStatus.priority {
                    return lhs.state.currentStatus.priority > rhs.state.currentStatus.priority
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Tag index

    var allTags: [String] {
        let tags = Set(monitors.flatMap(\.normalizedTags))
        return ["All"] + tags.sorted()
    }

    // MARK: - Status aggregates

    var unhealthyMonitors: [Monitor] {
        monitors.filter { $0.state.currentStatus == .down || $0.state.currentStatus == .degraded }
    }

    var overallStatus: MonitorStatus {
        if monitors.contains(where: { $0.state.currentStatus == .down })     { return .down }
        if monitors.contains(where: { $0.state.currentStatus == .degraded }) { return .degraded }
        if monitors.contains(where: { $0.state.currentStatus == .up })       { return .up }
        return .unknown
    }

    var summaryCounts: (up: Int, degraded: Int, down: Int, unknown: Int) {
        (
            up:       monitors.filter { $0.state.currentStatus == .up }.count,
            degraded: monitors.filter { $0.state.currentStatus == .degraded }.count,
            down:     monitors.filter { $0.state.currentStatus == .down }.count,
            unknown:  monitors.filter { $0.state.currentStatus == .unknown }.count
        )
    }

    var averageResponseTime: Double? {
        let values = monitors.compactMap(\.state.lastResponseTimeMs)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var overallUptime24h: Double? {
        let values = monitors.compactMap { uptime24h(for: $0.id) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
