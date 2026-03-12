# PulseBoard

PulseBoard is a lightweight native macOS dashboard for monitoring websites, APIs, TCP ports, and DNS targets. It runs locally, persists data on disk, stores secrets in Keychain, shows live health in a SwiftUI desktop interface, and can alert through macOS notifications, SMTP email, and Twilio-compatible SMS.

## What It Does

- Monitors HTTP/HTTPS websites and APIs with async `URLSession`
- Supports keyword/content validation, expected status codes, auth headers, and custom headers
- Tracks response time, 24h uptime, recent incidents, and SSL certificate expiry warnings
- Includes TCP connectivity checks and DNS resolution checks
- Runs concurrent scheduled checks with pause/resume and manual re-checks
- Sends local notifications, SMTP email alerts, and SMS alerts with routing and cooldowns
- Adds a menu bar extra with overall status and quick actions
- Persists monitors, settings, incidents, and recent check history in JSON
- Stores sensitive tokens and passwords in Keychain

## Architecture

- `AppModel`: main `ObservableObject` coordinating UI state, persistence, alerts, import/export, and engine updates
- `MonitoringEngine`: lightweight actor that schedules monitor loops and manual runs
- `MonitorCheckService`: performs HTTP, TCP, and DNS checks
- `AlertingService`: dispatches local notifications, SMTP email, and SMS
- `AppStore`: JSON persistence in `Application Support/PulseBoard/state.json`
- `KeychainStore`: secure storage for SMTP passwords, SMS tokens, and monitor bearer tokens

The app uses a local-first MVVM-style structure with focused services and value-type models.

## Running in Xcode

1. Open `PulseBoard.xcodeproj` in Xcode 26 or newer.
2. Select the `PulseBoard` scheme.
3. Choose the `My Mac` destination.
4. Press Run.

You can also build from Terminal:

```bash
xcodebuild -project PulseBoard.xcodeproj -scheme PulseBoard -destination 'platform=macOS' build
```

## Notifications and Capabilities

- On first run, open Settings and request notification permission.
- Local notifications use `UNUserNotificationCenter`.
- Launch at login uses `SMAppService.mainApp`. In some unsigned local development contexts, macOS may refuse registration; the app handles that gracefully.

## SMTP Configuration

PulseBoard includes a minimal built-in SMTP client intended for lightweight alerting.

- Recommended: use an SMTP relay that supports implicit TLS/SSL on port `465`
- Configure:
  - host
  - port
  - username
  - password or app password
  - from address
  - one or more recipient addresses
  - TLS/SSL toggle
- The SMTP password is stored in Keychain and never written to the JSON state file.

Notes:

- v1 uses implicit TLS when enabled.
- For providers that require advanced STARTTLS-only negotiation or OAuth-specific flows, use a compatible relay/app password setup.

## SMS Configuration

- Provider abstraction is included through `SMSClient`
- v1 implements a Twilio-compatible REST sender
- Configure:
  - API base URL, normally `https://api.twilio.com`
  - account SID
  - auth token
  - sender number
  - recipient numbers
- The SMS auth token is stored in Keychain

## Import / Export

- Export writes monitors, settings, incidents, and recent checks to JSON
- Import accepts either:
  - a full PulseBoard export
  - a JSON array of `Monitor` objects
  - a JSON object with a top-level `monitors` array

## Seed Data

On first launch, PulseBoard seeds three example monitors:

- Apple homepage HTTPS check
- GitHub API check
- HTTPBin keyword check
