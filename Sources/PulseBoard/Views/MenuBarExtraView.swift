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
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(model.settings.pauseAllMonitoring ? "Resume Monitoring" : "Pause Monitoring") {
                Task {
                    await model.setPauseAllMonitoring(!model.settings.pauseAllMonitoring)
                }
            }

            Button("Run All Checks Now") {
                Task {
                    await model.runAllNow()
                }
            }

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
