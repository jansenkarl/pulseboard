import AppKit
import SwiftUI
import UserNotifications

// MARK: - Termination delegate

/// Hooks into `applicationWillTerminate` so we can flush the latest in-memory
/// settings to disk *synchronously* before the process exits.  The standard
/// async `persistNow()` path may not complete in the narrow window that macOS
/// grants between SIGTERM and process death; this bypass writes directly on
/// the main thread and returns before the OS proceeds with termination.
@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    /// Called by AppKit on the main thread just before the process exits.
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            print("[PulseBoard] applicationWillTerminate: flushing state to disk")
            model?.terminationFlush()
            print("[PulseBoard] applicationWillTerminate: flush complete")
        }
    }

    /// Ensures local notifications are still visibly presented when PulseBoard
    /// is frontmost (e.g. Settings "Send Test" while app is active).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - App entry point

@main
struct PulseBoardApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_260, minHeight: 820)
                .task {
                    // Wire the termination delegate to the shared model so it
                    // can call terminationFlush() when the app is about to die.
                    appDelegate.model = model

                    // Route foreground notifications through the delegate so
                    // local test alerts are visibly presented while app is open.
                    UNUserNotificationCenter.current().delegate = appDelegate
                }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 880, height: 760)
        }

        MenuBarExtra(
            "PulseBoard",
            systemImage: model.overallStatus.symbolName,
            isInserted: Binding(
                get: { model.settings.showMenuBarIcon },
                set: { _ in }
            )
        ) {
            MenuBarExtraView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
