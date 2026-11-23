import OrtusKit
import UIKit
import UserNotifications

/// Apple's device token and notification taps reach the app here.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app once its model exists.
    @MainActor static var model: AppModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await Self.model?.registerPush(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// While the app is open, a notification still shows as a banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap opens the tab the notification belongs to.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let path = response.notification.request.content.userInfo["path"] as? String
        await MainActor.run { Self.model?.tab = Push.tab(for: path) }
    }
}

extension AppModel {
    /// Asks once whether the person wants notifications; with a yes, the
    /// phone registers with Apple (and then with the installation). Only on
    /// a phone: the simulator's tests see no question.
    func startPush() {
        #if targetEnvironment(simulator)
        return
        #else
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                Ringer.shared.start()
            }
        }
        #endif
    }

    /// The VoIP token came (or changed): the installation learns it with
    /// the ordinary one, so calls ring on this phone.
    func registerVoip(_ token: Data) async {
        if let apns = apnsToken { await registerPush(apns) }
    }

    func registerPush(_ deviceToken: Data) async {
        apnsToken = deviceToken
        guard let client, client.token != nil else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let offset = TimeZone.current.secondsFromGMT() / 60
        // Off on this installation (or refused): nothing to keep.
        guard let registration = try? await client.registerPush(token: deviceToken, voip: Ringer.shared.voipToken, sandbox: sandbox, utcOffsetMinutes: offset) else { return }
        PushStore.save(registration, server: client.server)
    }

    /// Before the session ends: the installation forgets this phone.
    func stopPush() async {
        guard let client, let registration = PushStore.load(server: client.server) else { return }
        try? await client.unregisterPush(id: registration.id)
        PushStore.remove(server: client.server)
    }
}
