import Foundation

actor SMSClient {
    func send(message: String, configuration: SMSConfiguration, authToken: String?) async throws {
        guard configuration.isConfigured else {
            throw SMSError.missingConfiguration
        }
        guard let baseURL = URL(string: configuration.apiBaseURL) else {
            throw SMSError.invalidBaseURL
        }
        guard let authToken, !authToken.isEmpty else {
            throw SMSError.missingConfiguration
        }

        switch configuration.provider {
        case .twilioCompatible:
            try await sendViaTwilioCompatible(message: message, configuration: configuration, baseURL: baseURL, authToken: authToken)
        case .custom:
            throw SMSError.unsupportedProvider
        }
    }

    private func sendViaTwilioCompatible(message: String, configuration: SMSConfiguration, baseURL: URL, authToken: String) async throws {
        let session = URLSession(configuration: .ephemeral)
        let accountPath = "/2010-04-01/Accounts/\(configuration.accountSID)/Messages.json"
        let endpoint = baseURL.appending(path: accountPath)

        for recipient in configuration.recipientNumbers where !recipient.isEmpty {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let authString = "\(configuration.accountSID):\(authToken)"
            request.setValue("Basic \(Data(authString.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")

            let params = [
                URLQueryItem(name: "From", value: configuration.senderNumber),
                URLQueryItem(name: "To", value: recipient),
                URLQueryItem(name: "Body", value: message)
            ]

            var components = URLComponents()
            components.queryItems = params
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                throw SMSError.requestFailed
            }
        }
    }
}

enum SMSError: LocalizedError {
    case missingConfiguration
    case invalidBaseURL
    case unsupportedProvider
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "SMS is not fully configured."
        case .invalidBaseURL:
            return "The SMS API base URL is invalid."
        case .unsupportedProvider:
            return "Only Twilio-compatible SMS is implemented in v1."
        case .requestFailed:
            return "The SMS request failed."
        }
    }
}
