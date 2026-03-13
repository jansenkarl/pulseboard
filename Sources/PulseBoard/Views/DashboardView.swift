import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    private var liveResponseSamples: [(date: Date, responseTimeMs: Double)] {
        let checkSamples = model.checksByMonitor.values
            .flatMap { $0 }
            .sorted { $0.checkedAt > $1.checkedAt }
            .prefix(30)
            .compactMap { check -> (Date, Double)? in
                guard let response = check.responseTimeMs else { return nil }
                return (check.checkedAt, response)
            }
            .reversed()

        if !checkSamples.isEmpty {
            return Array(checkSamples)
        }

        return model.monitors
            .compactMap { monitor -> (Date, Double)? in
                guard let checkedAt = monitor.state.lastCheckedAt,
                      let response = monitor.state.lastResponseTimeMs else { return nil }
                return (checkedAt, response)
            }
            .sorted { $0.0 < $1.0 }
    }

    private var liveResponseValues: [Double] {
        liveResponseSamples.map(\.responseTimeMs)
    }

    private var liveResponseStartDate: Date? {
        liveResponseSamples.first?.date
    }

    private var liveResponseEndDate: Date? {
        liveResponseSamples.last?.date
    }

    private var groupedMonitors: [(String, [Monitor])] {
        Dictionary(grouping: model.monitors) { monitor in
            monitor.normalizedTags.first ?? "Untagged"
        }
        .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
        .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                    MetricCard(
                        title: "Healthy",
                        value: "\(model.summaryCounts.up)",
                        subtitle: "\(model.monitors.count) total monitors",
                        tint: MonitorStatus.up.tint,
                        systemImage: "checkmark.circle.fill"
                    )
                    MetricCard(
                        title: "Warnings",
                        value: "\(model.summaryCounts.degraded)",
                        subtitle: model.summaryCounts.degraded == 0 ? "No degraded services" : "Need attention",
                        tint: MonitorStatus.degraded.tint,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    MetricCard(
                        title: "Failures",
                        value: "\(model.summaryCounts.down)",
                        subtitle: model.summaryCounts.down == 0 ? "No outages now" : "Immediate action needed",
                        tint: MonitorStatus.down.tint,
                        systemImage: "xmark.circle.fill"
                    )
                    MetricCard(
                        title: "24h Uptime",
                        value: PulseFormatters.percentage(model.overallUptime24h),
                        subtitle: "Across all monitor samples",
                        tint: Color.accentColor,
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }

                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Recent Incidents")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(model.incidents.count)")
                                    .foregroundStyle(.secondary)
                            }

                            if model.incidents.isEmpty {
                                Text("No incidents recorded yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(model.incidents.prefix(5)) { incident in
                                    incidentRow(incident)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Live Response Profile")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text(PulseFormatters.milliseconds(model.averageResponseTime))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(alignment: .top, spacing: 10) {
                                LatencyScaleYAxis(values: liveResponseValues)
                                SparklineView(values: liveResponseValues, tint: model.overallStatus.tint)
                            }
                            ChartTimeRangeLegend(
                                startDate: liveResponseStartDate,
                                endDate: liveResponseEndDate
                            )
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent("Overall State", value: model.overallStatus.label)
                                LabeledContent("Last Incident", value: PulseFormatters.relativeTime(model.incidents.first?.timestamp))
                                LabeledContent("Menu Bar Summary", value: "\(model.unhealthyMonitors.count) unhealthy")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Monitor Groups")
                            .font(.title3.weight(.semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(groupedMonitors, id: \.0) { group, monitors in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(group)
                                            .font(.headline)
                                        Spacer()
                                        Text("\(monitors.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(monitors.prefix(4)) { monitor in
                                        Button {
                                            model.selectedSection = .monitors
                                            model.selectedMonitorID = monitor.id
                                        } label: {
                                            HStack {
                                                StatusBadge(status: monitor.state.currentStatus)
                                                Text(monitor.name)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(PulseFormatters.milliseconds(monitor.state.lastResponseTimeMs))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(16)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Monitor Snapshot")
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Text("\(model.monitors.count) monitors")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(model.filteredMonitors.prefix(8)) { monitor in
                            Button {
                                model.selectedSection = .monitors
                                model.selectedMonitorID = monitor.id
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: monitor.kind.symbolName)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(monitor.name)
                                            .font(.headline)
                                        Text(monitor.displayTarget)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    StatusBadge(status: monitor.state.currentStatus)
                                    Text(PulseFormatters.percentage(model.uptime24h(for: monitor.id)))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .trailing)
                                    Text(PulseFormatters.milliseconds(monitor.state.lastResponseTimeMs))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 74, alignment: .trailing)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            if monitor.id != model.filteredMonitors.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PulseBoard")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Native macOS monitoring for sites, APIs, ports, and DNS with local-first alerting.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                StatusBadge(status: model.overallStatus)
                Text("Average latency \(PulseFormatters.milliseconds(model.averageResponseTime))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func incidentRow(_ incident: Incident) -> some View {
        Button {
            model.selectedSection = .monitors
            model.selectedMonitorID = incident.monitorID
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(incident.type.tint)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(incident.title)
                        .font(.headline)
                    Text(incident.monitorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(incident.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(PulseFormatters.relativeTime(incident.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
