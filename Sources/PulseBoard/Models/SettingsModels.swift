import Foundation

enum AlertChannelKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case localNotification
    case email
    case sms

    var id: String { rawValue }
}

struct AlertRoute: Codable, Hashable, Sendable {
    var appliesToAllMonitors: Bool = true
    var monitorIDs: [UUID] = []
    var tags: [String] = []

    private enum CodingKeys: String, CodingKey {
        case appliesToAllMonitors
        case monitorIDs
        case tags
    }

    init() {}

    init(appliesToAllMonitors: Bool = true, monitorIDs: [UUID] = [], tags: [String] = []) {
        self.appliesToAllMonitors = appliesToAllMonitors
        self.monitorIDs = monitorIDs
        self.tags = tags
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appliesToAllMonitors = try container.decodeIfPresent(Bool.self, forKey: .appliesToAllMonitors) ?? true
        monitorIDs = try container.decodeIfPresent([UUID].self, forKey: .monitorIDs) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func matches(monitor: Monitor) -> Bool {
        if appliesToAllMonitors {
            return true
        }
        if monitorIDs.contains(monitor.id) {
            return true
        }
        let normalizedTags = Set(tags.map { $0.lowercased() })
        if normalizedTags.isEmpty {
            return false
        }
        return !Set(monitor.normalizedTags.map { $0.lowercased() }).isDisjoint(with: normalizedTags)
    }
}

struct SMTPConfiguration: Codable, Hashable, Sendable {
    var host: String = ""
    var port: Int = 465
    var username: String = ""
    var passwordReference: String?
    var fromAddress: String = ""
    var toAddresses: [String] = []
    var useTLS: Bool = true

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case username
        case passwordReference
        case fromAddress
        case toAddresses
        case useTLS
    }

    init() {}

    init(
        host: String = "",
        port: Int = 465,
        username: String = "",
        passwordReference: String? = nil,
        fromAddress: String = "",
        toAddresses: [String] = [],
        useTLS: Bool = true
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.passwordReference = passwordReference
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
        self.useTLS = useTLS
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 465
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        passwordReference = try container.decodeIfPresent(String.self, forKey: .passwordReference)
        fromAddress = try container.decodeIfPresent(String.self, forKey: .fromAddress) ?? ""
        toAddresses = try container.decodeIfPresent([String].self, forKey: .toAddresses) ?? []
        useTLS = try container.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
    }

    var isConfigured: Bool {
        !host.isEmpty && !fromAddress.isEmpty && !toAddresses.isEmpty
    }
}

enum SMSProviderKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case twilioCompatible
    case custom

    var id: String { rawValue }
}

struct SMSConfiguration: Codable, Hashable, Sendable {
    var provider: SMSProviderKind = .twilioCompatible
    var apiBaseURL: String = "https://api.twilio.com"
    var accountSID: String = ""
    var authTokenReference: String?
    var senderNumber: String = ""
    var recipientNumbers: [String] = []

    private enum CodingKeys: String, CodingKey {
        case provider
        case apiBaseURL
        case accountSID
        case authTokenReference
        case senderNumber
        case recipientNumbers
    }

    init() {}

    init(
        provider: SMSProviderKind = .twilioCompatible,
        apiBaseURL: String = "https://api.twilio.com",
        accountSID: String = "",
        authTokenReference: String? = nil,
        senderNumber: String = "",
        recipientNumbers: [String] = []
    ) {
        self.provider = provider
        self.apiBaseURL = apiBaseURL
        self.accountSID = accountSID
        self.authTokenReference = authTokenReference
        self.senderNumber = senderNumber
        self.recipientNumbers = recipientNumbers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(SMSProviderKind.self, forKey: .provider) ?? .twilioCompatible
        apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? "https://api.twilio.com"
        accountSID = try container.decodeIfPresent(String.self, forKey: .accountSID) ?? ""
        authTokenReference = try container.decodeIfPresent(String.self, forKey: .authTokenReference)
        senderNumber = try container.decodeIfPresent(String.self, forKey: .senderNumber) ?? ""
        recipientNumbers = try container.decodeIfPresent([String].self, forKey: .recipientNumbers) ?? []
    }

    var isConfigured: Bool {
        !accountSID.isEmpty && !senderNumber.isEmpty && !recipientNumbers.isEmpty
    }
}

struct AlertChannelSettings: Codable, Hashable, Sendable {
    var isEnabled: Bool = false
    var route: AlertRoute = .init()

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case route
    }

    init() {}

    init(isEnabled: Bool = false, route: AlertRoute = .init()) {
        self.isEnabled = isEnabled
        self.route = route
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        route = try container.decodeIfPresent(AlertRoute.self, forKey: .route) ?? .init()
    }
}

struct MonitoringDefaults: Codable, Hashable, Sendable {
    var defaultTimeout: TimeInterval = 10
    var defaultInterval: TimeInterval = 60
    var retryCount: Int = 1
    var cooldownInterval: TimeInterval = 900
    var retentionDays: Int = 14

    private enum CodingKeys: String, CodingKey {
        case defaultTimeout
        case defaultInterval
        case retryCount
        case cooldownInterval
        case retentionDays
    }

    init() {}

    init(
        defaultTimeout: TimeInterval = 10,
        defaultInterval: TimeInterval = 60,
        retryCount: Int = 1,
        cooldownInterval: TimeInterval = 900,
        retentionDays: Int = 14
    ) {
        self.defaultTimeout = defaultTimeout
        self.defaultInterval = defaultInterval
        self.retryCount = retryCount
        self.cooldownInterval = cooldownInterval
        self.retentionDays = retentionDays
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .defaultTimeout) ?? 10
        defaultInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .defaultInterval) ?? 60
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 1
        cooldownInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownInterval) ?? 900
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 14
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    var pauseAllMonitoring: Bool = false
    var showMenuBarIcon: Bool = true
    var launchAtLogin: Bool = false
    var monitoring: MonitoringDefaults = .init()
    var localAlerts: AlertChannelSettings = .init(isEnabled: true, route: .init())
    var emailAlerts: AlertChannelSettings = .init()
    var smsAlerts: AlertChannelSettings = .init()
    var smtp: SMTPConfiguration = .init()
    var sms: SMSConfiguration = .init()

    private enum CodingKeys: String, CodingKey {
        case pauseAllMonitoring
        case showMenuBarIcon
        case launchAtLogin
        case monitoring
        case localAlerts
        case emailAlerts
        case smsAlerts
        case smtp
        case sms
    }

    init() {}

    init(
        pauseAllMonitoring: Bool = false,
        showMenuBarIcon: Bool = true,
        launchAtLogin: Bool = false,
        monitoring: MonitoringDefaults = .init(),
        localAlerts: AlertChannelSettings = .init(isEnabled: true, route: .init()),
        emailAlerts: AlertChannelSettings = .init(),
        smsAlerts: AlertChannelSettings = .init(),
        smtp: SMTPConfiguration = .init(),
        sms: SMSConfiguration = .init()
    ) {
        self.pauseAllMonitoring = pauseAllMonitoring
        self.showMenuBarIcon = showMenuBarIcon
        self.launchAtLogin = launchAtLogin
        self.monitoring = monitoring
        self.localAlerts = localAlerts
        self.emailAlerts = emailAlerts
        self.smsAlerts = smsAlerts
        self.smtp = smtp
        self.sms = sms
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pauseAllMonitoring = try container.decodeIfPresent(Bool.self, forKey: .pauseAllMonitoring) ?? false
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        monitoring = try container.decodeIfPresent(MonitoringDefaults.self, forKey: .monitoring) ?? .init()
        localAlerts = try container.decodeIfPresent(AlertChannelSettings.self, forKey: .localAlerts) ?? .init(isEnabled: true, route: .init())
        emailAlerts = try container.decodeIfPresent(AlertChannelSettings.self, forKey: .emailAlerts) ?? .init()
        smsAlerts = try container.decodeIfPresent(AlertChannelSettings.self, forKey: .smsAlerts) ?? .init()
        smtp = try container.decodeIfPresent(SMTPConfiguration.self, forKey: .smtp) ?? .init()
        sms = try container.decodeIfPresent(SMSConfiguration.self, forKey: .sms) ?? .init()
    }
}

struct SettingsDraft: Hashable, Sendable {
    var settings: AppSettings = .init()
    var smtpPassword: String = ""
    var smsAuthToken: String = ""
    var smtpToAddressesText: String = ""
    var smsRecipientsText: String = ""
    var localAlertRouteMode: RouteMode = .all
    var emailAlertRouteMode: RouteMode = .all
    var smsAlertRouteMode: RouteMode = .all
    var localRouteTagsText: String = ""
    var emailRouteTagsText: String = ""
    var smsRouteTagsText: String = ""
    var localRouteMonitorIDs: Set<UUID> = []
    var emailRouteMonitorIDs: Set<UUID> = []
    var smsRouteMonitorIDs: Set<UUID> = []

    enum RouteMode: String, CaseIterable, Identifiable, Hashable, Sendable {
        case all
        case tags
        case monitors

        var id: String { rawValue }
    }

    init() {}

    init(settings: AppSettings) {
        self.settings = settings
        smtpToAddressesText = settings.smtp.toAddresses.joined(separator: ", ")
        smsRecipientsText = settings.sms.recipientNumbers.joined(separator: ", ")
        localAlertRouteMode = SettingsDraft.routeMode(for: settings.localAlerts.route)
        emailAlertRouteMode = SettingsDraft.routeMode(for: settings.emailAlerts.route)
        smsAlertRouteMode = SettingsDraft.routeMode(for: settings.smsAlerts.route)
        localRouteTagsText = settings.localAlerts.route.tags.joined(separator: ", ")
        emailRouteTagsText = settings.emailAlerts.route.tags.joined(separator: ", ")
        smsRouteTagsText = settings.smsAlerts.route.tags.joined(separator: ", ")
        localRouteMonitorIDs = Set(settings.localAlerts.route.monitorIDs)
        emailRouteMonitorIDs = Set(settings.emailAlerts.route.monitorIDs)
        smsRouteMonitorIDs = Set(settings.smsAlerts.route.monitorIDs)
    }

    private static func routeMode(for route: AlertRoute) -> RouteMode {
        if route.appliesToAllMonitors {
            return .all
        }
        if !route.monitorIDs.isEmpty {
            return .monitors
        }
        return .tags
    }
}

struct AppDocumentState: Codable, Sendable {
    var monitors: [Monitor]
    var incidents: [Incident]
    var checksByMonitor: [UUID: [MonitorCheck]]
    var settings: AppSettings

    private enum CodingKeys: String, CodingKey {
        case monitors
        case incidents
        case checksByMonitor
        case settings
    }

    init(monitors: [Monitor], incidents: [Incident], checksByMonitor: [UUID: [MonitorCheck]], settings: AppSettings) {
        self.monitors = monitors
        self.incidents = incidents
        self.checksByMonitor = checksByMonitor
        self.settings = settings
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monitors, forKey: .monitors)
        try container.encode(incidents, forKey: .incidents)
        // Always encode checksByMonitor with explicit String keys so Foundation
        // writes a proper JSON object rather than a flat alternating array.
        let stringKeyed = Dictionary(uniqueKeysWithValues: checksByMonitor.map { ($0.key.uuidString, $0.value) })
        try container.encode(stringKeyed, forKey: .checksByMonitor)
        try container.encode(settings, forKey: .settings)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitors = try container.decodeIfPresent([Monitor].self, forKey: .monitors) ?? Monitor.sampleMonitors
        incidents = try container.decodeIfPresent([Incident].self, forKey: .incidents) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .init()
        // Decode checksByMonitor using explicit String keys (current on-disk format).
        // If that fails — e.g. the file contains the legacy flat alternating-array format
        // written by older Foundation/Swift — fall back to an empty history rather than
        // throwing and wiping out monitors and settings.
        if let stringKeyed = try? container.decodeIfPresent([String: [MonitorCheck]].self, forKey: .checksByMonitor) {
            checksByMonitor = Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        } else {
            checksByMonitor = [:]
        }
    }

    static let seeded = AppDocumentState(
        monitors: Monitor.sampleMonitors,
        incidents: [],
        checksByMonitor: [:],
        settings: .init()
    )
}
