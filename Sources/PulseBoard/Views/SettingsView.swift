import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = SettingsDraft()
    @State private var exportDocument = ConfigurationDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showSavedConfirmation = false

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    GlassCard {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsSection("General") {
                                Toggle("Pause all monitoring", isOn: $draft.settings.pauseAllMonitoring)
                                Toggle("Launch at login", isOn: $draft.settings.launchAtLogin)
                            }

                            Divider()

                            settingsSection("Notifications") {
                                LabeledContent("Permission Status", value: PulseFormatters.notificationStatus(model.notificationAuthorizationStatus))
                                Toggle("Enable local notifications", isOn: $draft.settings.localAlerts.isEnabled)
                                Button("Request Notification Permission") {
                                    Task {
                                        await model.requestNotificationPermission()
                                    }
                                }
                                routeEditor(
                                    title: "Local notification routing",
                                    mode: $draft.localAlertRouteMode,
                                    selectedMonitorIDs: $draft.localRouteMonitorIDs,
                                    tagsText: $draft.localRouteTagsText
                                )
                                Button("Send Test Notification") {
                                    Task {
                                        await model.sendTestAlert(.localNotification, using: draft)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsSection("SMTP Email") {
                                TextField("Host", text: $draft.settings.smtp.host)
                                TextField("Port", value: $draft.settings.smtp.port, format: .number)
                                TextField("Username", text: $draft.settings.smtp.username)
                                SecureField("Password / App Password", text: $draft.smtpPassword)
                                TextField("From Address", text: $draft.settings.smtp.fromAddress)
                                TextField("To Addresses", text: $draft.smtpToAddressesText)
                                Toggle("Use TLS/SSL", isOn: $draft.settings.smtp.useTLS)
                                Toggle("Enable email alerts", isOn: $draft.settings.emailAlerts.isEnabled)
                                routeEditor(
                                    title: "Email routing",
                                    mode: $draft.emailAlertRouteMode,
                                    selectedMonitorIDs: $draft.emailRouteMonitorIDs,
                                    tagsText: $draft.emailRouteTagsText
                                )
                                Button("Send Test Email") {
                                    Task {
                                        await model.sendTestAlert(.email, using: draft)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsSection("SMS Alerts") {
                                Picker("Provider", selection: $draft.settings.sms.provider) {
                                    ForEach(SMSProviderKind.allCases) { provider in
                                        Text(provider.rawValue).tag(provider)
                                    }
                                }
                                TextField("API Base URL", text: $draft.settings.sms.apiBaseURL)
                                TextField("Account SID", text: $draft.settings.sms.accountSID)
                                SecureField("Auth Token", text: $draft.smsAuthToken)
                                TextField("Sender Number", text: $draft.settings.sms.senderNumber)
                                TextField("Recipient Numbers", text: $draft.smsRecipientsText)
                                Toggle("Enable SMS alerts", isOn: $draft.settings.smsAlerts.isEnabled)
                                routeEditor(
                                    title: "SMS routing",
                                    mode: $draft.smsAlertRouteMode,
                                    selectedMonitorIDs: $draft.smsRouteMonitorIDs,
                                    tagsText: $draft.smsRouteTagsText
                                )
                                Button("Send Test SMS") {
                                    Task {
                                        await model.sendTestAlert(.sms, using: draft)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsSection("Monitoring Defaults") {
                                TextField("Default Timeout (seconds)", value: $draft.settings.monitoring.defaultTimeout, format: .number)
                                TextField("Default Interval (seconds)", value: $draft.settings.monitoring.defaultInterval, format: .number)
                                Stepper("Retry Count: \(draft.settings.monitoring.retryCount)", value: $draft.settings.monitoring.retryCount, in: 1 ... 5)
                                TextField("Cooldown Interval (seconds)", value: $draft.settings.monitoring.cooldownInterval, format: .number)
                                Stepper("Retention Days: \(draft.settings.monitoring.retentionDays)", value: $draft.settings.monitoring.retentionDays, in: 1 ... 180)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Data")
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 12) {
                                Button("Export Configuration") {
                                    Task {
                                        exportDocument = await model.exportDocument()
                                        isExporting = true
                                    }
                                }
                                Button("Import Monitors") {
                                    isImporting = true
                                }
                            }
                            Text("Exports monitors, settings, and recent state to JSON. Imports monitor definitions from a previous export or a plain monitor array.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Apply Settings") {
                            Task {
                                let didApply = await model.applySettings(draft)
                                if didApply {
                                    showSavedConfirmation = true
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
            }
        }
        // Runs on view appearance AND whenever model.settings changes (e.g. after
        // applySettings commits). Loads Keychain secrets so SecureFields show
        // dots rather than appearing blank when a password was previously stored.
        .task(id: model.settings) {
            draft = await model.settingsDraft()
        }
        .alert("Settings Saved", isPresented: $showSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your settings have been saved successfully.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "PulseBoard-Configuration"
        ) { result in
            if case .failure(let error) = result {
                model.transientMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await model.importMonitors(from: url)
                }
            case .failure(let error):
                model.transientMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Control alert delivery, secure channel credentials, retention, and monitoring defaults.")
                .foregroundStyle(.secondary)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }

    @ViewBuilder
    private func routeEditor(
        title: String,
        mode: Binding<SettingsDraft.RouteMode>,
        selectedMonitorIDs: Binding<Set<UUID>>,
        tagsText: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Picker("Route Mode", selection: mode) {
                ForEach(SettingsDraft.RouteMode.allCases) { routeMode in
                    Text(routeMode.rawValue.capitalized).tag(routeMode)
                }
            }
            .pickerStyle(.segmented)

            switch mode.wrappedValue {
            case .all:
                Text("This channel applies to every monitor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .tags:
                TextField("Production, APIs", text: tagsText)
            case .monitors:
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.monitors) { monitor in
                        Toggle(
                            monitor.name,
                            isOn: Binding(
                                get: { selectedMonitorIDs.wrappedValue.contains(monitor.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedMonitorIDs.wrappedValue.insert(monitor.id)
                                    } else {
                                        selectedMonitorIDs.wrappedValue.remove(monitor.id)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
