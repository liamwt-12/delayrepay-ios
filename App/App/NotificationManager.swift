import UserNotifications

/// Manages notification category registration and related utilities.
class NotificationManager {

    static let shared = NotificationManager()

    private init() {}

    /// Register custom notification categories so iOS renders action buttons.
    /// The server includes the category identifier in the push payload's aps.category field.
    func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_SERVICES",
            title: "View Services",
            options: [.foreground]
        )

        let claimAction = UNNotificationAction(
            identifier: "VIEW_CLAIM",
            title: "View Claim",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )

        // Daily briefing: "Your 08:15 to Kings Cross — On Time, Platform 3"
        let briefingCategory = UNNotificationCategory(
            identifier: "COMMUTE_BRIEFING",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Delay detected: "Your 08:15 is 18 minutes late. Claim ready."
        let delayCategory = UNNotificationCategory(
            identifier: "DELAY_DETECTED",
            actions: [claimAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Claim deadline approaching
        let deadlineCategory = UNNotificationCategory(
            identifier: "CLAIM_DEADLINE",
            actions: [claimAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Generic fallback
        let generalCategory = UNNotificationCategory(
            identifier: "GENERAL",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            briefingCategory,
            delayCategory,
            deadlineCategory,
            generalCategory
        ])
    }
}
