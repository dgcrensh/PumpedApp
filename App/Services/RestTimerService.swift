import Foundation
import OSLog
import UserNotifications

/// The rest timer's local notification (spec §6.2): one pending notification at the saved
/// `restTimerEndsAt`, so the user hears it with the app in the background or the screen locked.
///
/// `sync(_:)` is idempotent: it schedules for whatever the session holds right now, or cancels when
/// no rest is running. Call it after anything that changes the timer or the workout's phase.
@MainActor
enum RestTimerService {
    private static let logger = Logger(subsystem: "com.dgcrensh.pumped", category: "RestTimer")
    private static let notificationID = "rest-timer"

    /// UI tests run against a throwaway store and mustn't stop on the permission alert.
    private static var isEnabled: Bool {
        !CommandLine.arguments.contains("-ui-testing-reset-store")
    }

    /// Asks once for permission to notify; iOS only shows the prompt the first time.
    static func requestPermission() async {
        guard isEnabled else { return }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification permission request failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func sync(_ session: WorkoutSession) {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        let remaining = WorkoutFlow.restTimer(of: session).remaining(at: .now)
        guard session.endedAt == nil, session.phase == .lifting, remaining >= 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest's over"
        if let name = WorkoutFlow.currentEntry(of: session)?.exercise?.name {
            content.body = "Time for your next set of \(name)."
        } else {
            content.body = "Time for your next set."
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)) { error in
            if let error {
                Task { @MainActor in
                    logger.error("Scheduling the rest notification failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    static func cancel() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
