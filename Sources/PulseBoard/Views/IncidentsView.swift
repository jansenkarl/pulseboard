import SwiftUI

struct IncidentsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GlassCard {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Incidents")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Spacer()
                        Text("\(model.incidents.count) events")
                            .foregroundStyle(.secondary)
                    }

                    if model.incidents.isEmpty {
                        EmptyStateView(
                            title: "No Incidents Yet",
                            message: "Once monitors begin transitioning between healthy, degraded, and failed states, incidents will appear here.",
                            systemImage: "checkmark.shield"
                        )
                    } else {
                        ForEach(model.incidents) { incident in
                            Button {
                                model.selectedSection = .monitors
                                model.selectedMonitorID = incident.monitorID
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(incident.type.tint)
                                        .frame(width: 10, height: 44)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(incident.title)
                                                .font(.headline)
                                            Spacer()
                                            Text(PulseFormatters.time(incident.timestamp))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(incident.monitorName)
                                            .foregroundStyle(.secondary)
                                        Text(incident.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(16)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
