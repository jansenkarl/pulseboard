import Foundation

enum MonitorKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case http
    case keyword
    case tcp
    case dns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http:
            return "HTTP / API"
        case .keyword:
            return "Keyword Match"
        case .tcp:
            return "TCP Port"
        case .dns:
            return "DNS Resolve"
        }
    }

    var shortTitle: String {
        switch self {
        case .http:
            return "HTTP"
        case .keyword:
            return "Keyword"
        case .tcp:
            return "TCP"
        case .dns:
            return "DNS"
        }
    }
}

enum HTTPMethod: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"

    var id: String { rawValue }
}

enum MonitorStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case up
    case degraded
    case down
    case unknown

    var priority: Int {
        switch self {
        case .down:
            return 3
        case .degraded:
            return 2
        case .unknown:
            return 1
        case .up:
            return 0
        }
    }
}

struct HTTPHeader: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var key: String = ""
    var value: String = ""

    private enum CodingKeys: String, CodingKey {
        case id, key, value
    }

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
}

struct MonitorState: Codable, Hashable, Sendable {
    var currentStatus: MonitorStatus = .unknown
    var lastCheckedAt: Date?
    var lastResponseTimeMs: Double?
    var lastStatusCode: Int?
    var lastMessage: String?
    var lastSSLExpiryDate: Date?
    var lastResolvedAddresses: [String] = []
    var consecutiveFailures: Int = 0
    var lastAlertAt: Date?
    var lastAlertStatus: MonitorStatus?
    var lastTransitionAt: Date?

    private enum CodingKeys: String, CodingKey {
        case currentStatus, lastCheckedAt, lastResponseTimeMs, lastStatusCode
        case lastMessage, lastSSLExpiryDate, lastResolvedAddresses
        case consecutiveFailures, lastAlertAt, lastAlertStatus, lastTransitionAt
    }

    init(
        currentStatus: MonitorStatus = .unknown,
        lastCheckedAt: Date? = nil,
        lastResponseTimeMs: Double? = nil,
        lastStatusCode: Int? = nil,
        lastMessage: String? = nil,
        lastSSLExpiryDate: Date? = nil,
        lastResolvedAddresses: [String] = [],
        consecutiveFailures: Int = 0,
        lastAlertAt: Date? = nil,
        lastAlertStatus: MonitorStatus? = nil,
        lastTransitionAt: Date? = nil
    ) {
        self.currentStatus = currentStatus
        self.lastCheckedAt = lastCheckedAt
        self.lastResponseTimeMs = lastResponseTimeMs
        self.lastStatusCode = lastStatusCode
        self.lastMessage = lastMessage
        self.lastSSLExpiryDate = lastSSLExpiryDate
        self.lastResolvedAddresses = lastResolvedAddresses
        self.consecutiveFailures = consecutiveFailures
        self.lastAlertAt = lastAlertAt
        self.lastAlertStatus = lastAlertStatus
        self.lastTransitionAt = lastTransitionAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentStatus = try container.decodeIfPresent(MonitorStatus.self, forKey: .currentStatus) ?? .unknown
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastResponseTimeMs = try container.decodeIfPresent(Double.self, forKey: .lastResponseTimeMs)
        lastStatusCode = try container.decodeIfPresent(Int.self, forKey: .lastStatusCode)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastSSLExpiryDate = try container.decodeIfPresent(Date.self, forKey: .lastSSLExpiryDate)
        lastResolvedAddresses = try container.decodeIfPresent([String].self, forKey: .lastResolvedAddresses) ?? []
        consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        lastAlertAt = try container.decodeIfPresent(Date.self, forKey: .lastAlertAt)
        lastAlertStatus = try container.decodeIfPresent(MonitorStatus.self, forKey: .lastAlertStatus)
        lastTransitionAt = try container.decodeIfPresent(Date.self, forKey: .lastTransitionAt)
    }
}

struct Monitor: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var kind: MonitorKind
    var target: String
    var port: Int?
    var method: HTTPMethod = .get
    var expectedStatusCodes: [Int] = [200]
    var timeout: TimeInterval
    var interval: TimeInterval
    var tags: [String] = []
    var keyword: String?
    var bearerTokenReference: String?
    var customHeaders: [HTTPHeader] = []
    var isEnabled: Bool = true
    var notifyOnFailure: Bool = true
    var notifyOnRecovery: Bool = true
    var slowThreshold: TimeInterval?
    var sslWarningDays: Int = 14
    var retryCount: Int = 1
    var state: MonitorState = .init()

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, target, port, method, expectedStatusCodes
        case timeout, interval, tags, keyword, bearerTokenReference
        case customHeaders, isEnabled, notifyOnFailure, notifyOnRecovery
        case slowThreshold, sslWarningDays, retryCount, state
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: MonitorKind,
        target: String,
        port: Int? = nil,
        method: HTTPMethod = .get,
        expectedStatusCodes: [Int] = [200],
        timeout: TimeInterval,
        interval: TimeInterval,
        tags: [String] = [],
        keyword: String? = nil,
        bearerTokenReference: String? = nil,
        customHeaders: [HTTPHeader] = [],
        isEnabled: Bool = true,
        notifyOnFailure: Bool = true,
        notifyOnRecovery: Bool = true,
        slowThreshold: TimeInterval? = nil,
        sslWarningDays: Int = 14,
        retryCount: Int = 1,
        state: MonitorState = .init()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.target = target
        self.port = port
        self.method = method
        self.expectedStatusCodes = expectedStatusCodes
        self.timeout = timeout
        self.interval = interval
        self.tags = tags
        self.keyword = keyword
        self.bearerTokenReference = bearerTokenReference
        self.customHeaders = customHeaders
        self.isEnabled = isEnabled
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnRecovery = notifyOnRecovery
        self.slowThreshold = slowThreshold
        self.sslWarningDays = sslWarningDays
        self.retryCount = retryCount
        self.state = state
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(MonitorKind.self, forKey: .kind)
        target = try container.decode(String.self, forKey: .target)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        method = try container.decodeIfPresent(HTTPMethod.self, forKey: .method) ?? .get
        expectedStatusCodes = try container.decodeIfPresent([Int].self, forKey: .expectedStatusCodes) ?? [200]
        timeout = try container.decode(TimeInterval.self, forKey: .timeout)
        interval = try container.decode(TimeInterval.self, forKey: .interval)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
        bearerTokenReference = try container.decodeIfPresent(String.self, forKey: .bearerTokenReference)
        customHeaders = try container.decodeIfPresent([HTTPHeader].self, forKey: .customHeaders) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        notifyOnFailure = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFailure) ?? true
        notifyOnRecovery = try container.decodeIfPresent(Bool.self, forKey: .notifyOnRecovery) ?? true
        slowThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .slowThreshold)
        sslWarningDays = try container.decodeIfPresent(Int.self, forKey: .sslWarningDays) ?? 14
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 1
        state = try container.decodeIfPresent(MonitorState.self, forKey: .state) ?? .init()
    }

    var normalizedTags: [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var displayTarget: String {
        switch kind {
        case .http, .keyword:
            return target
        case .tcp:
            if let port {
                return "\(target):\(port)"
            }
            return target
        case .dns:
            return target
        }
    }

    var allowsStatusCodeValidation: Bool {
        switch kind {
        case .http, .keyword:
            return true
        case .tcp, .dns:
            return false
        }
    }

    var allowsHeaders: Bool {
        switch kind {
        case .http, .keyword:
            return true
        case .tcp, .dns:
            return false
        }
    }

    var supportsSSLInspection: Bool {
        switch kind {
        case .http, .keyword:
            return target.lowercased().hasPrefix("https://")
        case .tcp, .dns:
            return false
        }
    }
}

struct MonitorCheck: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var monitorID: UUID
    var checkedAt: Date
    var resultingStatus: MonitorStatus
    var responseTimeMs: Double?
    var statusCode: Int?
    var detail: String?
    var errorMessage: String?
    var matchedKeyword: Bool?
    var sslExpiryDate: Date?
    var resolvedAddresses: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, monitorID, checkedAt, resultingStatus, responseTimeMs
        case statusCode, detail, errorMessage, matchedKeyword, sslExpiryDate, resolvedAddresses
    }

    init(
        id: UUID = UUID(),
        monitorID: UUID,
        checkedAt: Date,
        resultingStatus: MonitorStatus,
        responseTimeMs: Double? = nil,
        statusCode: Int? = nil,
        detail: String? = nil,
        errorMessage: String? = nil,
        matchedKeyword: Bool? = nil,
        sslExpiryDate: Date? = nil,
        resolvedAddresses: [String] = []
    ) {
        self.id = id
        self.monitorID = monitorID
        self.checkedAt = checkedAt
        self.resultingStatus = resultingStatus
        self.responseTimeMs = responseTimeMs
        self.statusCode = statusCode
        self.detail = detail
        self.errorMessage = errorMessage
        self.matchedKeyword = matchedKeyword
        self.sslExpiryDate = sslExpiryDate
        self.resolvedAddresses = resolvedAddresses
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        monitorID = try container.decode(UUID.self, forKey: .monitorID)
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        resultingStatus = try container.decode(MonitorStatus.self, forKey: .resultingStatus)
        responseTimeMs = try container.decodeIfPresent(Double.self, forKey: .responseTimeMs)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        matchedKeyword = try container.decodeIfPresent(Bool.self, forKey: .matchedKeyword)
        sslExpiryDate = try container.decodeIfPresent(Date.self, forKey: .sslExpiryDate)
        resolvedAddresses = try container.decodeIfPresent([String].self, forKey: .resolvedAddresses) ?? []
    }
}

enum IncidentType: String, Codable, CaseIterable, Hashable, Sendable {
    case failure
    case recovery
    case warning
}

struct Incident: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var monitorID: UUID
    var monitorName: String
    var type: IncidentType
    var status: MonitorStatus
    var title: String
    var message: String
    var timestamp: Date
}

struct MonitorDraft: Hashable, Sendable {
    var id: UUID?
    var name: String = ""
    var kind: MonitorKind = .http
    var target: String = ""
    var portText: String = "443"
    var method: HTTPMethod = .get
    var expectedStatusCodesText: String = "200"
    var timeout: Double = 10
    var interval: Double = 60
    var tagsText: String = ""
    var keyword: String = ""
    var bearerToken: String = ""
    var customHeaders: [HTTPHeader] = []
    var isEnabled: Bool = true
    var notifyOnFailure: Bool = true
    var notifyOnRecovery: Bool = true
    var slowThresholdEnabled: Bool = false
    var slowThreshold: Double = 1.5
    var sslWarningDays: Int = 14
    var retryCount: Int = 1

    init() {}

    init(monitor: Monitor) {
        id = monitor.id
        name = monitor.name
        kind = monitor.kind
        target = monitor.target
        portText = monitor.port.map(String.init) ?? ""
        method = monitor.method
        expectedStatusCodesText = monitor.expectedStatusCodes.map(String.init).joined(separator: ", ")
        timeout = monitor.timeout
        interval = monitor.interval
        tagsText = monitor.tags.joined(separator: ", ")
        keyword = monitor.keyword ?? ""
        customHeaders = monitor.customHeaders
        isEnabled = monitor.isEnabled
        notifyOnFailure = monitor.notifyOnFailure
        notifyOnRecovery = monitor.notifyOnRecovery
        if let slowThreshold = monitor.slowThreshold {
            slowThresholdEnabled = true
            self.slowThreshold = slowThreshold
        }
        sslWarningDays = monitor.sslWarningDays
        retryCount = monitor.retryCount
    }
}

extension Monitor {
    static let sampleMonitors: [Monitor] = [
        Monitor(
            name: "Apple Homepage",
            kind: .http,
            target: "https://www.apple.com",
            timeout: 10,
            interval: 60,
            tags: ["Production", "Web"],
            slowThreshold: 2.0,
            sslWarningDays: 21,
            retryCount: 1
        ),
        Monitor(
            name: "GitHub API",
            kind: .http,
            target: "https://api.github.com",
            timeout: 12,
            interval: 90,
            tags: ["APIs", "Production"],
            customHeaders: [
                HTTPHeader(key: "Accept", value: "application/vnd.github+json"),
                HTTPHeader(key: "User-Agent", value: "PulseBoard")
            ],
            slowThreshold: 1.5,
            sslWarningDays: 21,
            retryCount: 2
        ),
        Monitor(
            name: "HTTPBin Keyword Check",
            kind: .keyword,
            target: "https://httpbin.org/json",
            timeout: 12,
            interval: 120,
            tags: ["Staging", "Keyword"],
            keyword: "slideshow",
            slowThreshold: 2.2,
            sslWarningDays: 14,
            retryCount: 1
        )
    ]
}
