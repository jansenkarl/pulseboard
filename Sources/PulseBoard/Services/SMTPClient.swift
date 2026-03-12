import Foundation

actor SMTPClient {
    func send(subject: String, body: String, configuration: SMTPConfiguration, password: String?) async throws {
        guard configuration.isConfigured else {
            throw SMTPError.missingConfiguration
        }

        try await Task.detached(priority: .utility) {
            let conversation = SMTPConversation(configuration: configuration, password: password)
            try conversation.send(subject: subject, body: body)
        }.value
    }
}

private struct SMTPConversation {
    let configuration: SMTPConfiguration
    let password: String?

    func send(subject: String, body: String) throws {
        let tlsMode = SMTPTLSMode(port: configuration.port, useTLS: configuration.useTLS)
        let transport = try SMTPTransport(host: configuration.host, port: configuration.port, tlsMode: tlsMode)
        defer { transport.close() }

        try transport.open()
        _ = try transport.readResponse(expectedPrefix: 220, stage: "server greeting")
        let ehlo = try sendHello(using: transport, stage: "EHLO")

        if tlsMode == .startTLS {
            if let ehlo, !ehlo.supports(capability: "STARTTLS") {
                throw SMTPError.connectionFailed("SMTP server did not advertise STARTTLS on port \(configuration.port). Use TLS/SSL on port 465, or choose a STARTTLS-capable submission port.")
            }
            _ = try transport.sendCommand("STARTTLS", expectingAnyOf: [220], stage: "STARTTLS")
            try transport.enableTLS()
            _ = try sendHello(using: transport, stage: "post-TLS EHLO")
        }

        if !configuration.username.isEmpty, let password, !password.isEmpty {
            try transport.sendCommand("AUTH LOGIN", expectingAnyOf: [334], stage: "AUTH LOGIN")
            try transport.sendRaw(configuration.username.base64Encoded() + "\r\n")
            _ = try transport.readResponse(expectedPrefix: 334, stage: "AUTH username challenge")
            try transport.sendRaw(password.base64Encoded() + "\r\n")
            _ = try transport.readResponse(expectedPrefix: 235, stage: "AUTH password challenge")
        }

        do {
            try transport.sendCommand("MAIL FROM:<\(configuration.fromAddress)>", expectingAnyOf: [250], stage: "MAIL FROM")
        } catch {
            throw enrichMailFromError(error)
        }

        for address in configuration.toAddresses where !address.isEmpty {
            try transport.sendCommand("RCPT TO:<\(address)>", expectingAnyOf: [250, 251], stage: "RCPT TO")
        }

        try transport.sendCommand("DATA", expectingAnyOf: [354], stage: "DATA")
        let message = formattedMessage(subject: subject, body: body)
        try transport.sendRaw(message + "\r\n.\r\n")
        _ = try transport.readResponse(expectedPrefix: 250, stage: "message body")
        _ = try? transport.sendCommand("QUIT", expectingAnyOf: [221], stage: "QUIT")
    }

    private func enrichMailFromError(_ error: Error) -> Error {
        let host = configuration.host.lowercased()
        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromAddress = configuration.fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard host.contains("gmail.com"),
              !username.isEmpty,
              !fromAddress.isEmpty,
              username.caseInsensitiveCompare(fromAddress) != .orderedSame else {
            return error
        }

        let hint = "Gmail may reject MAIL FROM when authenticated as \(username) but From is \(fromAddress). Use the Gmail account as From, or configure \(fromAddress) as a verified alias in Gmail."
        return SMTPError.connectionFailed("\(error.localizedDescription)\n\n\(hint)")
    }

    private func formattedMessage(subject: String, body: String) -> String {
        let recipients = configuration.toAddresses.joined(separator: ", ")
        return [
            "From: \(configuration.fromAddress)",
            "To: \(recipients)",
            "Subject: \(subject)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "",
            body
        ].joined(separator: "\r\n")
    }

    private func sendHello(using transport: SMTPTransport, stage: String) throws -> SMTPResponse? {
        do {
            return try transport.sendCommand("EHLO pulseboard.local", expectingAnyOf: [250], stage: stage)
        } catch let error as SMTPError where error.canFallbackToHELO(during: stage) {
            _ = try transport.sendCommand("HELO pulseboard.local", expectingAnyOf: [250], stage: "HELO fallback")
            return nil
        }
    }
}

private final class SMTPTransport {
    private let commandTimeout: TimeInterval = 20
    private let openTimeout: TimeInterval = 10
    private let host: String
    private let port: Int
    private let tlsMode: SMTPTLSMode
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var scheduledRunLoop: RunLoop?

    init(host: String, port: Int, tlsMode: SMTPTLSMode) throws {
        self.host = host
        self.port = port
        self.tlsMode = tlsMode
    }

    func open() throws {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)

        guard let readStream, let writeStream else {
            throw SMTPError.connectionFailed("Unable to create SMTP streams.")
        }

        inputStream = readStream.takeRetainedValue()
        outputStream = writeStream.takeRetainedValue()

        let runLoop = RunLoop.current
        scheduledRunLoop = runLoop
        inputStream?.schedule(in: runLoop, forMode: .default)
        outputStream?.schedule(in: runLoop, forMode: .default)

        if tlsMode == .implicit {
            try setTLSSettings()
        }

        inputStream?.open()
        outputStream?.open()
        try waitUntilOpen()
    }

    func close() {
        if let runLoop = scheduledRunLoop {
            inputStream?.remove(from: runLoop, forMode: .default)
            outputStream?.remove(from: runLoop, forMode: .default)
        }
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        scheduledRunLoop = nil
    }

    func enableTLS() throws {
        try setTLSSettings()
    }

    @discardableResult
    func sendCommand(_ command: String, expectingAnyOf expectedCodes: [Int], stage: String) throws -> SMTPResponse {
        try sendRaw(command + "\r\n")
        let response = try readResponse(expectedPrefix: expectedCodes.first ?? 250, allowedPrefixes: expectedCodes, stage: stage)
        if !expectedCodes.contains(response.code) {
            throw SMTPError.unexpectedResponse("Unexpected SMTP response during \(stage): \(response.message)")
        }
        return response
    }

    func sendRaw(_ command: String) throws {
        guard let outputStream else {
            throw SMTPError.connectionFailed("Output stream unavailable.")
        }

        let bytes = Array(command.utf8)
        var sent = 0
        let deadline = Date().addingTimeInterval(commandTimeout)

        while sent < bytes.count {
            if Date() >= deadline {
                throw SMTPError.connectionFailed("Timed out writing SMTP command.")
            }

            if outputStream.streamStatus == .error {
                throw outputStream.streamError ?? SMTPError.connectionFailed("SMTP write failed.")
            }

            guard outputStream.hasSpaceAvailable || outputStream.streamStatus == .open || outputStream.streamStatus == .writing else {
                pumpRunLoop(for: 0.05)
                continue
            }

            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return outputStream.write(baseAddress.advanced(by: sent), maxLength: bytes.count - sent)
            }

            if written <= 0 {
                if written == 0 {
                    pumpRunLoop(for: 0.05)
                    continue
                }
                throw outputStream.streamError ?? SMTPError.connectionFailed("SMTP write failed.")
            }

            sent += written
        }
    }

    func readResponse(expectedPrefix: Int, allowedPrefixes: [Int] = [], stage: String) throws -> SMTPResponse {
        guard let inputStream else {
            throw SMTPError.connectionFailed("Input stream unavailable.")
        }

        let validCodes = allowedPrefixes.isEmpty ? [expectedPrefix] : allowedPrefixes
        var responseText = ""
        let deadline = Date().addingTimeInterval(commandTimeout)

        while Date() < deadline {
            if inputStream.hasBytesAvailable {
                var buffer = [UInt8](repeating: 0, count: 2_048)
                let count = inputStream.read(&buffer, maxLength: buffer.count)
                if count > 0 {
                    responseText += String(decoding: buffer.prefix(count), as: UTF8.self)
                    if let parsed = parseSMTPResponse(from: responseText), validCodes.contains(parsed.code) {
                        return parsed
                    }
                    if let parsed = parseSMTPResponse(from: responseText), !validCodes.contains(parsed.code) {
                        throw SMTPError.unexpectedResponse("Unexpected SMTP response during \(stage): \(parsed.message)")
                    }
                } else if count < 0 {
                    throw inputStream.streamError ?? SMTPError.connectionFailed("SMTP read failed during \(stage).")
                }
            } else {
                if inputStream.streamStatus == .error {
                    throw inputStream.streamError ?? SMTPError.connectionFailed("SMTP stream failed during \(stage).")
                }

                if inputStream.streamStatus == .atEnd {
                    throw SMTPError.connectionFailed("SMTP connection closed by server during \(stage).")
                }

                pumpRunLoop(for: 0.05)
            }
        }

        throw SMTPError.connectionFailed("Timed out waiting for SMTP response during \(stage).")
    }

    private func waitUntilOpen() throws {
        let deadline = Date().addingTimeInterval(openTimeout)
        while Date() < deadline {
            let inputStatus = inputStream?.streamStatus ?? .notOpen
            let outputStatus = outputStream?.streamStatus ?? .notOpen
            if inputStatus == .open && outputStatus == .open {
                return
            }
            if inputStatus == .error || outputStatus == .error {
                throw inputStream?.streamError ?? outputStream?.streamError ?? SMTPError.connectionFailed("SMTP connection failed.")
            }
            pumpRunLoop(for: 0.05)
        }
        throw SMTPError.connectionFailed("Timed out opening SMTP connection.")
    }

    private func setTLSSettings() throws {
        let settings: [NSString: Any] = [
            kCFStreamSSLPeerName: host,
            kCFStreamSSLValidatesCertificateChain: true
        ]
        let sslKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)

        guard inputStream?.setProperty(settings, forKey: sslKey) == true,
              outputStream?.setProperty(settings, forKey: sslKey) == true else {
            throw SMTPError.connectionFailed("Unable to apply TLS settings for SMTP connection.")
        }
    }

    private func pumpRunLoop(for interval: TimeInterval) {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(interval))
    }

    private func parseSMTPResponse(from text: String) -> SMTPResponse? {
        var completeLines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") {
            if completeLines.last == "" {
                completeLines.removeLast()
            }
        } else if !completeLines.isEmpty {
            // Keep buffering until the current (unterminated) line is complete.
            completeLines.removeLast()
        }

        let parsedLines = completeLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(parseSMTPLine)

        guard let first = parsedLines.first else {
            return nil
        }

        if first.separator == " " {
            return SMTPResponse(code: first.code, message: first.text)
        }

        if let terminalIndex = parsedLines.firstIndex(where: { $0.code == first.code && $0.separator == " " }) {
            let message = parsedLines[...terminalIndex].map(\.text).joined(separator: "\n")
            return SMTPResponse(code: first.code, message: message)
        }

        let sawOnlyHyphenatedLinesForOneCode = !parsedLines.isEmpty && parsedLines.allSatisfy {
            $0.code == first.code && $0.separator == "-"
        }

        if text.hasSuffix("\n"), sawOnlyHyphenatedLinesForOneCode {
            let message = parsedLines.map(\.text).joined(separator: "\n")
            return SMTPResponse(code: first.code, message: message)
        }

        return nil
    }

    private func parseSMTPLine(_ line: String) -> ParsedSMTPLine? {
        guard line.count >= 4, let code = Int(line.prefix(3)) else {
            return nil
        }
        let separatorIndex = line.index(line.startIndex, offsetBy: 3)
        let separator = line[separatorIndex]
        guard separator == " " || separator == "-" else {
            return nil
        }
        return ParsedSMTPLine(code: code, separator: separator, text: line)
    }
}

private struct ParsedSMTPLine {
    let code: Int
    let separator: Character
    let text: String
}

private struct SMTPResponse {
    let code: Int
    let message: String

    func supports(capability: String) -> Bool {
        let needle = capability.uppercased()
        return message
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .contains { line in
                line.hasPrefix("250-") && line.dropFirst(4).contains(needle) ||
                line.hasPrefix("250 ") && line.dropFirst(4).contains(needle)
            }
    }
}

private enum SMTPTLSMode: Sendable {
    case none
    case implicit
    case startTLS

    init(port: Int, useTLS: Bool) {
        guard useTLS else {
            self = .none
            return
        }

        if port == 465 {
            self = .implicit
        } else {
            self = .startTLS
        }
    }
}

enum SMTPError: LocalizedError {
    case missingConfiguration
    case connectionFailed(String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "SMTP is not fully configured."
        case .connectionFailed(let message), .unexpectedResponse(let message):
            return message
        }
    }
}

private extension SMTPError {
    func canFallbackToHELO(during stage: String) -> Bool {
        switch self {
        case .unexpectedResponse:
            return true
        case .connectionFailed(let message):
            return message.localizedCaseInsensitiveContains("during \(stage)")
        case .missingConfiguration:
            return false
        }
    }
}

private extension String {
    func base64Encoded() -> String {
        Data(utf8).base64EncodedString()
    }
}
