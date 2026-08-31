import UserNotifications

enum Notifier {
    /// Fire-and-forget banner. Authorisation is requested lazily, on the first widget
    /// that actually asks to post one, rather than at launch.
    static func post(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
                  granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
