import Foundation
import os
import UserNotifications

/// Tells you when Macster turns itself off while its panel is closed, so you know why your Mac went to sleep.
///
/// It asks for provisional authorization, which shows no prompt: notifications arrive quietly in Notification Center,
/// and macOS offers there to show them more prominently or to turn them off.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called when you click a notification.
    var onOpen: (() -> Void)?

    private let log = Logger(subsystem: "io.github.macster", category: "notifications")

    /// UserNotifications needs an app bundle. Builds run with `swift run`, and the snapshot tool, aren't one.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return nil }
        return .current()
    }

    func prepare() {
        guard let center else { return }
        center.delegate = self
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .provisional])
                log.info("Notifications authorized: \(granted, privacy: .public)")
            } catch {
                log.error("Couldn't set up notifications: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func post(title: String, body: String) {
        guard center != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                log.error("Couldn't post a notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Macster is the active app while its panel is open; show notifications then too, rather than dropping them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { onOpen?() }
    }
}
