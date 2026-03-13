import Foundation

struct HelpSectionContent: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let summary: String
    let highlights: [String]
    let subsections: [HelpSubsectionContent]
}

struct HelpSubsectionContent: Identifiable {
    let id: String
    let title: String
    let intro: String
    let items: [HelpItemContent]
}

struct HelpItemContent: Identifiable {
    let id: String
    let title: String
    let description: String
}

enum HelpContent {
    static let sections: [HelpSectionContent] = [settings]

    static let settings = HelpSectionContent(
        id: "settings",
        title: "Settings",
        systemImage: "gearshape.fill",
        summary: "Use Settings to control app-wide behavior for monitoring, alert delivery, secure credentials, retention, and import/export tasks.",
        highlights: [
            "Click Apply Settings after making changes. PulseBoard saves the current page values, refreshes services, and shows a confirmation or error message.",
            "The test buttons save the current draft first, so tests run with the same values you see on screen.",
            "SMTP passwords and SMS auth tokens are stored in Keychain when possible. Exported configuration files intentionally omit those secrets.",
            "Monitoring defaults affect new monitors you create later. They do not retroactively rewrite existing monitor settings."
        ],
        subsections: [
            HelpSubsectionContent(
                id: "settings-general",
                title: "General",
                intro: "These controls affect PulseBoard at the application level rather than a specific alert channel.",
                items: [
                    HelpItemContent(
                        id: "general-pause-all-monitoring",
                        title: "Pause all monitoring",
                        description: "Temporarily stops scheduled checks for every monitor. Use this during maintenance windows or when you want to silence monitoring activity without deleting monitors. Turn it off to resume normal checking."
                    ),
                    HelpItemContent(
                        id: "general-launch-at-login",
                        title: "Launch at login",
                        description: "Starts PulseBoard automatically when you sign in to macOS. If macOS or the current environment blocks this change, PulseBoard restores the previous setting and shows an explanatory message."
                    )
                ]
            ),
            HelpSubsectionContent(
                id: "settings-notifications",
                title: "Notifications",
                intro: "This section controls local macOS notifications and decides which monitors can send them.",
                items: [
                    HelpItemContent(
                        id: "notifications-permission",
                        title: "Permission",
                        description: "Shows the current macOS notification authorization state for PulseBoard so you can confirm whether alerts are allowed, pending, or denied."
                    ),
                    HelpItemContent(
                        id: "notifications-enable-local",
                        title: "Enable local notifications",
                        description: "Master switch for in-app local alerts. Even with permission granted, local notifications are only sent when this toggle is on."
                    ),
                    HelpItemContent(
                        id: "notifications-request-permission",
                        title: "Request Permission / Check Permission",
                        description: "Requests notification access the first time, or re-checks the current permission state after permission has already been granted."
                    ),
                    HelpItemContent(
                        id: "notifications-send-test",
                        title: "Send Test",
                        description: "Saves the current settings draft, verifies permission, and sends a sample local notification so you can confirm delivery. The button is disabled only when notifications are explicitly denied."
                    ),
                    HelpItemContent(
                        id: "notifications-open-system-settings",
                        title: "Open System Settings",
                        description: "Appears when macOS has denied notifications. It opens the Notifications area in System Settings so you can enable alerts for PulseBoard."
                    ),
                    HelpItemContent(
                        id: "notifications-denied-message",
                        title: "Denied status message",
                        description: "When notifications are blocked, PulseBoard shows a reminder under the action buttons so you know the fix must be made in System Settings rather than inside the app."
                    ),
                    HelpItemContent(
                        id: "notifications-routing-scope",
                        title: "Local notification routing",
                        description: "Use Scope to choose whether this channel applies to all monitors, only monitors with matching tags, or only monitors you explicitly select."
                    ),
                    HelpItemContent(
                        id: "notifications-routing-tags",
                        title: "Tags field",
                        description: "When Scope is set to Tags, enter one or more tags separated by commas or new lines. A monitor matches if it shares at least one of those tags."
                    ),
                    HelpItemContent(
                        id: "notifications-routing-monitors",
                        title: "Choose monitors list",
                        description: "When Scope is set to Monitors, use the checklist to decide exactly which monitors can trigger local notifications."
                    )
                ]
            ),
            HelpSubsectionContent(
                id: "settings-smtp-email",
                title: "SMTP Email",
                intro: "Use this section to configure email alerts sent through an SMTP server or relay.",
                items: [
                    HelpItemContent(
                        id: "smtp-host",
                        title: "Host",
                        description: "The SMTP server hostname PulseBoard should connect to, such as smtp.example.com. Email tests and alerts cannot send until this is filled in."
                    ),
                    HelpItemContent(
                        id: "smtp-port",
                        title: "Port",
                        description: "The SMTP server port. Port 465 uses implicit TLS when TLS is enabled. Other ports use STARTTLS if the server supports it."
                    ),
                    HelpItemContent(
                        id: "smtp-username",
                        title: "Username",
                        description: "The login name used for SMTP authentication when your provider requires it. Leave it blank only if your mail server allows unauthenticated sending."
                    ),
                    HelpItemContent(
                        id: "smtp-password",
                        title: "Password",
                        description: "The SMTP password or app password. PulseBoard attempts to store it securely in Keychain so it is not written into exported configuration files."
                    ),
                    HelpItemContent(
                        id: "smtp-from-address",
                        title: "From Address",
                        description: "The sender address recipients will see. Some providers require this to match the authenticated account or one of its verified aliases."
                    ),
                    HelpItemContent(
                        id: "smtp-to-addresses",
                        title: "To Addresses",
                        description: "One or more destination email addresses separated by commas or new lines. PulseBoard sends alerts to every address in this list."
                    ),
                    HelpItemContent(
                        id: "smtp-use-tls",
                        title: "Use TLS / SSL",
                        description: "Encrypts the SMTP connection. Leave this on for most providers unless you intentionally use an unencrypted internal relay."
                    ),
                    HelpItemContent(
                        id: "smtp-enable-email-alerts",
                        title: "Enable email alerts",
                        description: "Master switch for email notifications. PulseBoard only attempts to send email alerts when this toggle is on and the route matches the affected monitor."
                    ),
                    HelpItemContent(
                        id: "smtp-routing",
                        title: "Email routing",
                        description: "Works the same way as local notification routing: choose All, Tags, or Monitors to control which monitors can trigger email alerts."
                    ),
                    HelpItemContent(
                        id: "smtp-send-test",
                        title: "Send Test Email",
                        description: "Saves the current draft, validates the email configuration, and sends a sample message. At minimum, Host, From Address, and To Addresses must be set, and credentials must be valid if your server requires authentication."
                    )
                ]
            ),
            HelpSubsectionContent(
                id: "settings-sms-alerts",
                title: "SMS Alerts",
                intro: "Use this section for text-message alerts delivered through a Twilio-compatible API.",
                items: [
                    HelpItemContent(
                        id: "sms-provider",
                        title: "Provider",
                        description: "Selects the SMS integration type. In the current version, only Twilio-compatible sending is implemented. Choosing Custom will not send live SMS alerts yet."
                    ),
                    HelpItemContent(
                        id: "sms-api-base-url",
                        title: "API Base URL",
                        description: "The root URL for your SMS provider API. The default Twilio-compatible value works for Twilio; custom endpoints must still be valid URLs."
                    ),
                    HelpItemContent(
                        id: "sms-account-sid",
                        title: "Account SID",
                        description: "The SMS account identifier used in authentication and request paths for Twilio-compatible APIs."
                    ),
                    HelpItemContent(
                        id: "sms-auth-token",
                        title: "Auth Token",
                        description: "The API secret used to authenticate SMS requests. PulseBoard attempts to save it in Keychain instead of exporting it in plain text."
                    ),
                    HelpItemContent(
                        id: "sms-sender-number",
                        title: "Sender Number",
                        description: "The phone number or sender ID the provider will use as the message origin. It must be valid for your SMS account."
                    ),
                    HelpItemContent(
                        id: "sms-recipients",
                        title: "Recipients",
                        description: "One or more destination numbers separated by commas or new lines. PulseBoard sends the same alert to each recipient in this list."
                    ),
                    HelpItemContent(
                        id: "sms-enable-alerts",
                        title: "Enable SMS alerts",
                        description: "Master switch for SMS delivery. Alerts are only attempted when this toggle is on and the selected route matches the monitor."
                    ),
                    HelpItemContent(
                        id: "sms-routing",
                        title: "SMS routing",
                        description: "Works the same way as the other routing editors. Use it to target all monitors, a tag-based subset, or specific named monitors."
                    ),
                    HelpItemContent(
                        id: "sms-send-test",
                        title: "Send Test SMS",
                        description: "Saves the current draft and sends a sample message to every configured recipient. To succeed, PulseBoard needs a valid API base URL, account SID, auth token, sender number, and at least one recipient."
                    )
                ]
            ),
            HelpSubsectionContent(
                id: "settings-monitoring-defaults",
                title: "Monitoring Defaults",
                intro: "These values are used as the starting defaults when you create a new monitor. PulseBoard also enforces minimum values when saving.",
                items: [
                    HelpItemContent(
                        id: "monitoring-timeout",
                        title: "Timeout (seconds)",
                        description: "Default maximum time a new monitor waits for a response before the check is treated as failed. Saved values lower than 2 seconds are raised to 2."
                    ),
                    HelpItemContent(
                        id: "monitoring-interval",
                        title: "Interval (seconds)",
                        description: "Default frequency for new monitor checks. Saved values lower than 15 seconds are raised to 15 so checks do not run too aggressively."
                    ),
                    HelpItemContent(
                        id: "monitoring-retry-count",
                        title: "Retry Count",
                        description: "Default number of consecutive failures a new monitor tolerates before escalating from a retry warning to an alert-worthy failure. Saved values lower than 1 are raised to 1."
                    ),
                    HelpItemContent(
                        id: "monitoring-cooldown",
                        title: "Cooldown (seconds)",
                        description: "Minimum time between repeated alerts for the same ongoing state. Saved values lower than 60 seconds are raised to 60."
                    ),
                    HelpItemContent(
                        id: "monitoring-retention-days",
                        title: "Retention Days",
                        description: "How long PulseBoard keeps historical checks and incidents before pruning older records during saves. Saved values lower than 1 day are raised to 1."
                    )
                ]
            ),
            HelpSubsectionContent(
                id: "settings-data",
                title: "Data",
                intro: "These actions move configuration into or out of PulseBoard without editing monitors one at a time.",
                items: [
                    HelpItemContent(
                        id: "data-export-configuration",
                        title: "Export Configuration",
                        description: "Creates a JSON export containing monitors plus non-secret settings. Passwords, SMS tokens, monitor runtime state, and other secrets are intentionally excluded."
                    ),
                    HelpItemContent(
                        id: "data-import-configuration",
                        title: "Import Configuration",
                        description: "Imports a full PulseBoard configuration export or a monitor-only JSON file. If imported items duplicate your existing data, PulseBoard asks whether to skip duplicates or import everything."
                    ),
                    HelpItemContent(
                        id: "data-import-merge-behavior",
                        title: "Import behavior",
                        description: "When settings are imported, PulseBoard preserves local Keychain references for existing SMTP and SMS secrets because exported files do not contain those secret values."
                    )
                ]
            )
        ]
    )
}