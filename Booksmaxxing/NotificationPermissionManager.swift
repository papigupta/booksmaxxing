import Foundation
import UserNotifications

final class NotificationPermissionManager {
    enum PromptReason {
        case firstSession
        case returningUser
    }

    static let shared = NotificationPermissionManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let promptedKey = "com.booksmaxxing.notifications.prompted"

    private init() {}

    var hasPrompted: Bool {
        defaults.bool(forKey: promptedKey)
    }

    func requestAuthorizationIfNeeded(reason _: PromptReason, completion: ((Bool) -> Void)? = nil) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                DispatchQueue.main.async { completion?(true) }
            case .denied:
                DispatchQueue.main.async { completion?(false) }
            case .notDetermined:
                if self.hasPrompted {
                    DispatchQueue.main.async { completion?(false) }
                    return
                }
                self.defaults.set(true, forKey: self.promptedKey)
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion?(granted) }
                }
            @unknown default:
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }
}
