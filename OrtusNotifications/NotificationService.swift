import OrtusKit
import UserNotifications

/// Shows a push with its notification's text, fetched from the
/// installation with this phone's fetch token. Without it (no token, no
/// network, too slow) the push shows Apple's generic "Something new".
final class NotificationService: UNNotificationServiceExtension {
    private var deliver: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        deliver = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        self.content = content
        guard let (id, server) = Push.parts(of: request.content.userInfo), let registration = PushStore.load(server: server) else {
            contentHandler(content)
            return
        }
        Task {
            if let notice = try? await Push.fetch(server: server, fetchToken: registration.fetch_token, id: id) {
                content.title = notice.title
                content.body = notice.detail ?? ""
                content.threadIdentifier = notice.app
                content.userInfo["path"] = notice.path ?? "/"
            }
            self.finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        finish()
    }

    private func finish() {
        guard let deliver, let content else { return }
        self.deliver = nil
        deliver(content)
    }
}
