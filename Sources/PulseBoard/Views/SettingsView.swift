import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = SettingsDraft()
    @State private var rowOneHeight: CGFloat = 0
    @State private var rowTwoHeight: CGFloat = 0
    @State private var rowThreeHeight: CGFloat = 0

    private let maxContentWidth: CGFloat = 980
    private let labelColumnWidth: CGFloat = 170
    private let controlMaxWidth: CGFloat = 340

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    // Row 1: General + Notifications
                    HStack(alignment: .top, spacing: 18) {
                        generalCard(minHeight: rowOneHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        notificationsCard(minHeight: rowOneHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .onPreferenceChange(SettingsRowOneHeightPreferenceKey.self) { rowOneHeight = $0 }

                    // Row 2: SMTP Email + SMS Alerts
                    HStack(alignment: .top, spacing: 18) {
                        smtpCard(minHeight: rowTwoHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        smsCard(minHeight: rowTwoHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .onPreferenceChange(SettingsRowTwoHeightPreferenceKey.self) { rowTwoHeight = $0 }

                    // Row 3: Monitoring Defaults + Data
                    HStack(alignment: .top, spacing: 18) {
                        monitoringDefaultsCard(minHeight: rowThreeHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        dataCard(minHeight: rowThreeHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .onPreferenceChange(SettingsRowThreeHeightPreferenceKey.self) { rowThreeHeight = $0 }

                    HStack {
                        Spacer()
                        Button("Apply Settings") {
                            Task {
                                let didApply = await model.applySettings(draft)
                                if didApply {
                                    model.transientMessage = "Your settings have been saved successfully."
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        // Runs on view appearance AND whenever model.settings changes (e.g. after
        // applySettings commits). Loads Keychain secrets so SecureFields show
        // dots rather than appearing blank when a password was previously stored.
        .task(id: model.settings) {
            draft = await model.settingsDraft()
        }
        .alert(
            "PulseBoard",
            isPresented: Binding(
                get: { model.transientMessage != nil },
                set: { newValue in
                    if !newValue {
                        model.transientMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.transientMessage = nil
            }
        } message: {
            Text(model.transientMessage ?? "")
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

    private func generalCard(minHeight: CGFloat) -> some View {
        settingsCard(minHeight: minHeight, measuredBy: SettingsRowOneHeightPreferenceKey.self) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("General")
                settingsToggleRow("Pause all monitoring", isOn: $draft.settings.pauseAllMonitoring)
                settingsToggleRow("Show menu bar icon", isOn: $draft.settings.showMenuBarIcon)
                settingsToggleRow("Launch at login", isOn: $draft.settings.launchAtLogin)
            }
        }
    }

    private func notificationsCard(minHeight: CGFloat) -> some View {
        settingsCard(minHeight: minHeight, measuredBy: SettingsRowOneHeightPreferenceKey.self) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Notifications")
                settingsValueRow("Permission", value: PulseFormatters.notificationStatus(model.notificationAuthorizationStatus))
                settingsToggleRow("Enable local notifications", isOn: $draft.settings.localAlerts.isEnabled)
                HStack(spacing: 10) {
                    Button(requestPermissionButtonTitle) {
                        Task {
                            await model.requestNotificationPermission()
                        }
                    }
                    Button("Send Test") {
                        Task {
                            await model.sendTestAlert(.localNotification, using: draft)
                        }
                    }
                    .disabled(!model.canSendLocalNotificationTest)

                    if model.notificationAuthorizationStatus == .denied {
                        Button("Open System Settings") {
                            model.openSystemNotificationSettings()
                        }
                    }
                }
                .buttonStyle(.bordered)

                if model.notificationAuthorizationStatus == .denied {
                    Text("Notifications are denied for PulseBoard. Enable them in System Settings → Notifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                routeEditor(
                    title: "Local notification routing",
                    mode: $draft.localAlertRouteMode,
                    selectedMonitorIDs: $draft.localRouteMonitorIDs,
                    tagsText: $draft.localRouteTagsText
                )
            }
        }
    }

    private var requestPermissionButtonTitle: String {
        model.notificationAuthorizationStatus == .authorized ? "Check Permission" : "Request Permission"
    }

    private func smtpCard(minHeight: CGFloat) -> some View {
        settingsCard(minHeight: minHeight, measuredBy: SettingsRowTwoHeightPreferenceKey.self) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("SMTP Email")
                settingsFieldRow("Host") {
                    TextField("smtp.example.com", text: $draft.settings.smtp.host)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Port") {
                    TextField("587", value: $draft.settings.smtp.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Username") {
                    TextField("notifications@company.com", text: $draft.settings.smtp.username)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Password") {
                    SecureField("App password", text: $draft.smtpPassword)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("From Address") {
                    TextField("status@company.com", text: $draft.settings.smtp.fromAddress)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("To Addresses") {
                    TextField("ops@company.com, oncall@company.com", text: $draft.smtpToAddressesText)
                        .textFieldStyle(.roundedBorder)
                }
                settingsToggleRow("Use TLS / SSL", isOn: $draft.settings.smtp.useTLS)
                settingsToggleRow("Enable email alerts", isOn: $draft.settings.emailAlerts.isEnabled)
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
                .buttonStyle(.bordered)
            }
        }
    }

    private func smsCard(minHeight: CGFloat) -> some View {
        settingsCard(minHeight: minHeight, measuredBy: SettingsRowTwoHeightPreferenceKey.self) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("SMS Alerts")
                settingsFieldRow("Provider") {
                    Picker("Provider", selection: $draft.settings.sms.provider) {
                        ForEach(SMSProviderKind.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                settingsFieldRow("API Base URL") {
                    TextField("https://api.twilio.com", text: $draft.settings.sms.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Account SID") {
                    TextField("ACxxxxxxxx", text: $draft.settings.sms.accountSID)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Auth Token") {
                    SecureField("Token", text: $draft.smsAuthToken)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Sender Number") {
                    TextField("+1 555 123 4567", text: $draft.settings.sms.senderNumber)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Recipients") {
                    TextField("+1 555 987 6543, +1 555 555 1212", text: $draft.smsRecipientsText)
                        .textFieldStyle(.roundedBorder)
                }
                settingsToggleRow("Enable SMS alerts", isOn: $draft.settings.smsAlerts.isEnabled)
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
                .buttonStyle(.bordered)
            }
        }
    }

    private func monitoringDefaultsCard(minHeight: CGFloat) -> some View {
        settingsCard(minHeight: minHeight, measuredBy: SettingsRowThreeHeightPreferenceKey.self) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Monitoring Defaults")
                settingsFieldRow("Timeout (seconds)") {
                    TextField("12", value: $draft.settings.monitoring.defaultTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Interval (seconds)") {
                    TextField("60", value: $draft.settings.monitoring.defaultInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Retry Count") {
                    Stepper(value: $draft.settings.monitoring.retryCount, in: 1 ... 5) {
                        Text("\(draft.settings.monitoring.retryCount)")
                    }
                }
                settingsFieldRow("Cooldown (seconds)") {
                    TextField("120", value: $draft.settings.monitoring.cooldownInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                settingsFieldRow("Retention Days") {
                    Stepper(value: $draft.settings.monitoring.retentionDays, in: 1 ... 180) {
                        Text("\(draft.settings.monitoring.retentionDays)")
                    }
                }
            }
        }
    }

    private func dataCard(minHeight: CGFloat) -> some View {
        settingsCard(minHeight: minHeight, measuredBy: SettingsRowThreeHeightPreferenceKey.self) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Data")
                HStack(spacing: 10) {
                    Button("Export Configuration") {
                        Task {
                            await model.presentExportConfigurationPanel()
                        }
                    }
                    Button("Import Configuration") {
                        Task {
                            await model.presentImportConfigurationPanel()
                        }
                    }
                }
                .buttonStyle(.bordered)
                Text("Exports portable configuration to JSON (monitors and non-secret settings). Imports full configuration from previous exports or monitor-only JSON files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsCard<Key: PreferenceKey, Content: View>(
        minHeight: CGFloat,
        measuredBy key: Key.Type,
        @ViewBuilder content: () -> Content
    ) -> some View where Key.Value == CGFloat {
        GlassCard {
            content()
                .reportHeight(using: key)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
    }

    private func settingsFieldRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)

                control()
                    .frame(maxWidth: controlMaxWidth, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
    }

    private func settingsToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: labelColumnWidth, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func settingsValueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: labelColumnWidth, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .frame(maxWidth: controlMaxWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func routeEditor(
        title: String,
        mode: Binding<SettingsDraft.RouteMode>,
        selectedMonitorIDs: Binding<Set<UUID>>,
        tagsText: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            settingsFieldRow("Scope") {
                Picker("Route Mode", selection: mode) {
                    ForEach(SettingsDraft.RouteMode.allCases) { routeMode in
                        Text(routeMode.rawValue.capitalized).tag(routeMode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            switch mode.wrappedValue {
            case .all:
                Text("This channel applies to every monitor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .tags:
                settingsFieldRow("Tags") {
                    TextField("Production, APIs", text: tagsText)
                        .textFieldStyle(.roundedBorder)
                }
            case .monitors:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose monitors")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct SettingsRowOneHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsRowTwoHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsRowThreeHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func reportHeight<Key: PreferenceKey>(using key: Key.Type) -> some View where Key.Value == CGFloat {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: key, value: proxy.size.height)
            }
        )
    }
}
