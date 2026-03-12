import SwiftUI

struct MonitorWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Monitors")
                        .font(.title3.weight(.semibold))

                    TextField("Search name, host, or tag", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.allTags, id: \.self) { tag in
                                Button {
                                    model.selectedTag = tag
                                } label: {
                                    TagChip(title: tag, isSelected: model.selectedTag == tag)
                                }
                            }
                        }
                    }

                    Table(model.filteredMonitors, selection: $model.selectedMonitorID) {
                        TableColumn("Monitor") { monitor in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(monitor.name)
                                    .font(.headline)
                                Text(monitor.displayTarget)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .width(min: 210, ideal: 250)

                        TableColumn("State") { monitor in
                            StatusBadge(status: monitor.state.currentStatus)
                        }
                        .width(110)

                        TableColumn("Latency") { monitor in
                            Text(PulseFormatters.milliseconds(monitor.state.lastResponseTimeMs))
                                .foregroundStyle(.secondary)
                        }
                        .width(80)

                        TableColumn("Uptime") { monitor in
                            Text(PulseFormatters.percentage(model.uptime24h(for: monitor.id)))
                                .foregroundStyle(.secondary)
                        }
                        .width(80)

                        TableColumn("SSL") { monitor in
                            Text(PulseFormatters.daysUntil(monitor.state.lastSSLExpiryDate))
                                .foregroundStyle(.secondary)
                        }
                        .width(70)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                }
            }
            .frame(minWidth: 520)

            if let selectedMonitor = model.monitor(for: model.selectedMonitorID) {
                MonitorDetailView(monitor: selectedMonitor)
            } else {
                GlassCard {
                    EmptyStateView(
                        title: "No Monitor Selected",
                        message: "Choose a monitor from the list or create a new one to see detailed status, uptime, and recent checks.",
                        systemImage: "display.2"
                    )
                }
            }
        }
    }
}

struct MonitorDetailView: View {
    @EnvironmentObject private var model: AppModel
    let monitor: Monitor

    private var history: [MonitorCheck] {
        model.checks(for: monitor.id)
    }

    private var latencyValues: [Double] {
        history.recent(limit: 24).compactMap(\.responseTimeMs).reversed()
    }

    var body: some View {
        GlassCard {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: monitor.kind.symbolName)
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(monitor.name)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                            }
                            Text(monitor.displayTarget)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                StatusBadge(status: monitor.state.currentStatus)
                                if !monitor.isEnabled {
                                    TagChip(title: "Paused", isSelected: true)
                                }
                                ForEach(monitor.normalizedTags, id: \.self) { tag in
                                    TagChip(title: tag)
                                }
                            }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Button("Run Now") {
                                Task {
                                    await model.runMonitorNow(monitor)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button(monitor.isEnabled ? "Pause" : "Resume") {
                                Task {
                                    await model.setMonitorEnabled(monitor.id, isEnabled: !monitor.isEnabled)
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Edit") {
                                model.openEditor(for: monitor)
                            }
                            .buttonStyle(.bordered)

                            Button("Delete", role: .destructive) {
                                Task {
                                    model.selectedMonitorID = monitor.id
                                    await model.deleteSelectedMonitor()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        MetricCard(
                            title: "Latency",
                            value: PulseFormatters.milliseconds(monitor.state.lastResponseTimeMs),
                            subtitle: "Most recent sample",
                            tint: monitor.state.currentStatus.tint,
                            systemImage: "speedometer"
                        )
                        MetricCard(
                            title: "Status Code",
                            value: PulseFormatters.statusCode(monitor.state.lastStatusCode),
                            subtitle: "Last HTTP response",
                            tint: Color.accentColor,
                            systemImage: "number"
                        )
                        MetricCard(
                            title: "24h Uptime",
                            value: PulseFormatters.percentage(model.uptime24h(for: monitor.id)),
                            subtitle: "Calculated from recent checks",
                            tint: MonitorStatus.up.tint,
                            systemImage: "chart.bar.xaxis"
                        )
                        MetricCard(
                            title: "SSL Expiry",
                            value: PulseFormatters.daysUntil(monitor.state.lastSSLExpiryDate),
                            subtitle: "Remaining certificate lifetime",
                            tint: MonitorStatus.degraded.tint,
                            systemImage: "lock.shield"
                        )
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Recent Performance")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("Last checked \(PulseFormatters.relativeTime(monitor.state.lastCheckedAt))")
                                    .foregroundStyle(.secondary)
                            }
                            SparklineView(values: latencyValues, tint: monitor.state.currentStatus.tint)
                            AvailabilityStrip(checks: history)
                            if let message = monitor.state.lastMessage {
                                Divider()
                                Text(message)
                                    .foregroundStyle(.secondary)
                            }
                            if !monitor.state.lastResolvedAddresses.isEmpty {
                                Text("Resolved: \(monitor.state.lastResolvedAddresses.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Recent Checks")
                                .font(.title3.weight(.semibold))

                            if history.isEmpty {
                                Text("No checks recorded yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(history.prefix(12)) { check in
                                    HStack(alignment: .top, spacing: 12) {
                                        StatusBadge(status: check.resultingStatus)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(PulseFormatters.time(check.checkedAt))
                                                .font(.headline)
                                            Text(check.errorMessage ?? check.detail ?? "Completed")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(PulseFormatters.milliseconds(check.responseTimeMs))
                                                .foregroundStyle(.secondary)
                                            Text(PulseFormatters.statusCode(check.statusCode))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    if check.id != history.prefix(12).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MonitorEditorView: View {
    @Binding var draft: MonitorDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(draft.id == nil ? "Add Monitor" : "Edit Monitor")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Form {
                Section("Basics") {
                    TextField("Name", text: $draft.name)
                    Picker("Monitor Type", selection: $draft.kind) {
                        ForEach(MonitorKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField(draft.kind == .tcp || draft.kind == .dns ? "Host" : "URL", text: $draft.target)
                    if draft.kind == .tcp {
                        TextField("Port", text: $draft.portText)
                    }
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }

                if draft.kind == .http || draft.kind == .keyword {
                    Section("HTTP") {
                        Picker("Method", selection: $draft.method) {
                            ForEach(HTTPMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        TextField("Expected Status Codes", text: $draft.expectedStatusCodesText)
                        SecureField("Bearer Token (optional)", text: $draft.bearerToken)
                        if draft.id != nil {
                            Text("Leave the bearer token blank to keep the stored Keychain value.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if draft.kind == .keyword {
                    Section("Content Validation") {
                        TextField("Expected Keyword", text: $draft.keyword)
                    }
                }

                if draft.kind == .http || draft.kind == .keyword {
                    Section("Headers") {
                        ForEach($draft.customHeaders) { $header in
                            HStack {
                                TextField("Header", text: $header.key)
                                TextField("Value", text: $header.value)
                            }
                        }
                        Button("Add Header") {
                            draft.customHeaders.append(HTTPHeader())
                        }
                    }
                }

                Section("Timing") {
                    HStack {
                        Text("Timeout")
                        Spacer()
                        Text("\(Int(draft.timeout))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draft.timeout, in: 2 ... 60, step: 1)

                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("\(Int(draft.interval))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draft.interval, in: 15 ... 600, step: 15)

                    Stepper("Retry Count: \(draft.retryCount)", value: $draft.retryCount, in: 1 ... 5)
                    Toggle("Slow Response Threshold", isOn: $draft.slowThresholdEnabled)
                    if draft.slowThresholdEnabled {
                        HStack {
                            Text("Warn Above")
                            Spacer()
                            Text(String(format: "%.1fs", draft.slowThreshold))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $draft.slowThreshold, in: 0.2 ... 10, step: 0.1)
                    }
                    Stepper("SSL Warning Days: \(draft.sslWarningDays)", value: $draft.sslWarningDays, in: 1 ... 90)
                }

                Section("Organization") {
                    TextField("Tags (comma separated)", text: $draft.tagsText)
                    Toggle("Notify on Failure", isOn: $draft.notifyOnFailure)
                    Toggle("Notify on Recovery", isOn: $draft.notifyOnRecovery)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 720, height: 760)
        .background(AppBackdrop().opacity(0.7))
    }
}
