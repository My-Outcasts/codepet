import Foundation
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var isAuthorized = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
            if let error = error {
                print("[Notifications] Authorization error: \(error.localizedDescription)")
            }
        }
    }

    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // Schedule daily reminder
    func scheduleDailyReminder(hour: Int = 9, minute: Int = 0) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Practice!"
        content.body = "Your CodePet is waiting. Let's learn something new today."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyReminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notifications] Failed to schedule: \(error.localizedDescription)")
            }
        }
    }

    // Streak warning
    func sendStreakNotification(streakDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak!"
        content.body = "You're on a \(streakDays)-day streak. Complete today's challenge to keep it going."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "streakWarning", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // Level up
    func sendLevelUpNotification(newLevel: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Level Up!"
        content.body = "You've reached Level \(newLevel). Your CodePet is getting stronger!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "levelUp-\(newLevel)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // Daily challenge reminder
    func sendDailyChallengeReminder(challengeTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Daily Challenge!"
        content.body = "Today's challenge: \(challengeTitle)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "dailyChallenge", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Delegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func removeDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyReminder"])
    }
}
