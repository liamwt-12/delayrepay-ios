import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    
    /// Queued notification payload from cold launch — delivered to WebView once nativeReady fires
    var pendingNotificationPayload: [AnyHashable: Any]?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Register custom notification categories with action buttons
        NotificationManager.shared.registerCategories()
        
        UNUserNotificationCenter.current().delegate = self
        
        // Check for cold launch from notification tap
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            pendingNotificationPayload = remoteNotification
        }
        
        // Start network monitoring
        NetworkMonitor.shared.start()
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        
        return true
    }

    // MARK: - Remote Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(
            name: .pushTokenReceived,
            object: token
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[PUSH] Registration failed: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground notification — show banner even when app is open
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Notification tap — forward to WebView
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        
        var payload = userInfo
        if actionId != UNNotificationDefaultActionIdentifier {
            payload["tappedAction"] = actionId
        }
        
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: payload
        )
        
        // Clear badge on interaction
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushTokenReceived = Notification.Name("PushTokenReceived")
    static let pushNotificationTapped = Notification.Name("PushNotificationTapped")
}
