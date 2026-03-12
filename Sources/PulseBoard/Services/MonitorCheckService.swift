import Foundation
import Network
import Security

actor MonitorCheckService {
    private let keychain: KeychainStore

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func performCheck(for monitor: Monitor) async -> MonitorCheck {
        switch monitor.kind {
        case .http, .keyword:
            return await performHTTPCheck(for: monitor)
        case .tcp:
            return await performTCPCheck(for: monitor)
        case .dns:
            return await performDNSCheck(for: monitor)
        }
    }

    private func performHTTPCheck(for monitor: Monitor) async -> MonitorCheck {
        let startDate = Date()
        guard let url = URL(string: monitor.target), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: .down,
                detail: "Invalid URL",
                errorMessage: "The monitor target is not a valid HTTP URL."
            )
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = monitor.method.rawValue
            request.timeoutInterval = monitor.timeout
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            for header in monitor.customHeaders where !header.key.isEmpty {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }
            if let tokenReference = monitor.bearerTokenReference,
               let token = try await keychain.readSecret(for: tokenReference),
               !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let delegate = TrustCapturingDelegate()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = monitor.timeout
            configuration.timeoutIntervalForResource = monitor.timeout
            configuration.waitsForConnectivity = false

            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }

            let startedAt = ContinuousClock.now
            let (data, response) = try await session.data(for: request)
            let elapsed = startedAt.duration(to: .now)
            let responseTimeMs = elapsed.milliseconds

            guard let httpResponse = response as? HTTPURLResponse else {
                return MonitorCheck(
                    monitorID: monitor.id,
                    checkedAt: startDate,
                    resultingStatus: .down,
                    responseTimeMs: responseTimeMs,
                    detail: "Invalid response",
                    errorMessage: "The endpoint did not return an HTTP response."
                )
            }

            var status: MonitorStatus = .up
            var detail = "Response OK"
            var errorMessage: String?
            var matchedKeyword: Bool?

            if !monitor.expectedStatusCodes.isEmpty && !monitor.expectedStatusCodes.contains(httpResponse.statusCode) {
                status = .down
                detail = "Unexpected status code"
                errorMessage = "Expected \(monitor.expectedStatusCodes.map(String.init).joined(separator: ", ")), received \(httpResponse.statusCode)."
            }

            if let keyword = monitor.keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
                let body = String(decoding: data, as: UTF8.self)
                matchedKeyword = body.localizedCaseInsensitiveContains(keyword)
                if matchedKeyword == false {
                    status = .down
                    detail = "Keyword missing"
                    errorMessage = "The expected keyword was not found in the response body."
                }
            }

            if let slowThreshold = monitor.slowThreshold, responseTimeMs > slowThreshold * 1_000, status != .down {
                status = .degraded
                detail = "Slow response"
            }

            let sslExpiryDate = delegate.sslExpiryDate
            if let sslExpiryDate, status != .down {
                let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: sslExpiryDate).day ?? 0
                if daysRemaining <= monitor.sslWarningDays {
                    status = .degraded
                    detail = "SSL certificate expires in \(max(daysRemaining, 0)) day(s)"
                }
            }

            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: status,
                responseTimeMs: responseTimeMs,
                statusCode: httpResponse.statusCode,
                detail: detail,
                errorMessage: errorMessage,
                matchedKeyword: matchedKeyword,
                sslExpiryDate: sslExpiryDate
            )
        } catch {
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: .down,
                detail: "Request failed",
                errorMessage: presentableNetworkError(error)
            )
        }
    }

    private func performTCPCheck(for monitor: Monitor) async -> MonitorCheck {
        let startDate = Date()
        guard !monitor.target.isEmpty, let port = monitor.port, port > 0, port <= 65_535 else {
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: .down,
                detail: "Invalid host or port",
                errorMessage: "A valid host and port are required for TCP checks."
            )
        }

        let startedAt = ContinuousClock.now
        do {
            try await TCPProbe.connect(host: monitor.target, port: port, timeout: monitor.timeout)
            let elapsed = startedAt.duration(to: .now).milliseconds
            let status: MonitorStatus = (monitor.slowThreshold.map { elapsed > $0 * 1_000 } ?? false) ? .degraded : .up
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: status,
                responseTimeMs: elapsed,
                detail: status == .degraded ? "Connection slow" : "Port reachable"
            )
        } catch {
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: .down,
                detail: "Connection failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func performDNSCheck(for monitor: Monitor) async -> MonitorCheck {
        let startDate = Date()
        guard !monitor.target.isEmpty else {
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: .down,
                detail: "Invalid hostname",
                errorMessage: "A hostname is required for DNS checks."
            )
        }

        let startedAt = ContinuousClock.now
        do {
            let addresses = try await DNSResolver.resolve(hostname: monitor.target)
            let elapsed = startedAt.duration(to: .now).milliseconds
            let status: MonitorStatus = (monitor.slowThreshold.map { elapsed > $0 * 1_000 } ?? false) ? .degraded : .up
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: status,
                responseTimeMs: elapsed,
                detail: addresses.isEmpty ? "No addresses returned" : "Resolved \(addresses.count) address(es)",
                resolvedAddresses: addresses
            )
        } catch {
            return MonitorCheck(
                monitorID: monitor.id,
                checkedAt: startDate,
                resultingStatus: .down,
                detail: "DNS lookup failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func presentableNetworkError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "The request timed out."
            case NSURLErrorCannotFindHost:
                return "The host could not be found."
            case NSURLErrorNotConnectedToInternet:
                return "The Mac is offline."
            case NSURLErrorSecureConnectionFailed:
                return "The SSL/TLS handshake failed."
            case NSURLErrorUserAuthenticationRequired:
                return "Authentication is required."
            default:
                return nsError.localizedDescription
            }
        default:
            return nsError.localizedDescription
        }
    }
}

private final class TrustCapturingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private(set) var sslExpiryDate: Date?

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let serverTrust = challenge.protectionSpace.serverTrust {
            sslExpiryDate = Self.extractExpiryDate(from: serverTrust)
        }
        return (.performDefaultHandling, nil)
    }

    private static func extractExpiryDate(from trust: SecTrust) -> Date? {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else {
            return nil
        }

        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [CFString: Any],
              let field = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let rawValue = field[kSecPropertyKeyValue] else {
            return nil
        }

        if let date = rawValue as? Date {
            return date
        }
        if let number = rawValue as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: number.doubleValue)
        }
        return nil
    }
}

private enum TCPProbe {
    static func connect(host: String, port: Int, timeout: TimeInterval) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp)
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: .global(qos: .utility))
        defer { connection.cancel() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            continuation.resume()
                        case .failed(let error):
                            continuation.resume(throwing: error)
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        default:
                            break
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw URLError(.timedOut)
            }

            guard let result = try await group.next() else {
                throw URLError(.cannotConnectToHost)
            }
            _ = result
            group.cancelAll()
        }
    }
}

private enum DNSResolver {
    static func resolve(hostname: String) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            var hints = addrinfo(
                ai_flags: AI_ADDRCONFIG,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: IPPROTO_TCP,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )

            var infoPointer: UnsafeMutablePointer<addrinfo>?
            let result = getaddrinfo(hostname, nil, &hints, &infoPointer)
            guard result == 0, let first = infoPointer else {
                let message = String(cString: gai_strerror(result))
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: [NSLocalizedDescriptionKey: message])
            }
            defer { freeaddrinfo(first) }

            var addresses: Set<String> = []
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let current = cursor {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let nameInfoResult = getnameinfo(
                    current.pointee.ai_addr,
                    current.pointee.ai_addrlen,
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if nameInfoResult == 0 {
                    let bytes = hostBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
                    addresses.insert(String(decoding: bytes, as: UTF8.self))
                }
                cursor = current.pointee.ai_next
            }

            return addresses.sorted()
        }.value
    }
}

private extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
