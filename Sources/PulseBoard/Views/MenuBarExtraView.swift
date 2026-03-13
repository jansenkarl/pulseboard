import AppKit
import SwiftUI

struct MenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusBadge(status: model.overallStatus)
                Spacer()
                Text("\(model.unhealthyMonitors.count) unhealthy")
                    .foregroundStyle(.secondary)
            }

            Divider()

            if model.unhealthyMonitors.isEmpty {
                Text("All monitors are healthy.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.unhealthyMonitors.prefix(5)) { monitor in
                    HStack {
                        Image(systemName: monitor.kind.symbolName)
                            .foregroundStyle(.secondary)
                        Text(monitor.name)
                        Spacer()
                        StatusBadge(status: monitor.state.currentStatus)
                    }
                }
            }

            Divider()

            Button("Open Dashboard") {
                focusMainWindow(at: .dashboard)
            }

            Button(model.settings.pauseAllMonitoring ? "Resume Monitoring" : "Pause Monitoring") {
                Task {
                    await model.setPauseAllMonitoring(!model.settings.pauseAllMonitoring)
                }
            }

            Button {
                Task {
                    await model.runAllNow()
                }
            } label: {
                if model.isRunningAllChecksNow {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running Checks…")
                    }
                } else {
                    Text("Run All Checks Now")
                }
            }
            .disabled(model.isRunningAllChecksNow)

            if let lastManualRunAt = model.lastManualRunAt {
                Text("Last manual run \(PulseFormatters.relativeTime(lastManualRunAt)) • \(model.lastManualRunCheckCount) checks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                focusMainWindow(at: .settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func focusMainWindow(at section: SidebarSection) {
        model.selectedSection = section
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = NSApp.windows.first(where: isPrimaryWindow) {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        openWindow(id: "main")
    }

    private func isPrimaryWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        guard window.toolbar != nil else { return false }
        let className = NSStringFromClass(type(of: window))
        return !className.contains("NSStatusBarWindow")
    }
}
