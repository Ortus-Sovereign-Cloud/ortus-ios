import CallKit
import Foundation
import OrtusKit
import PushKit
import UIKit

/// A call rings like a phone call: PushKit wakes the app for a call's VoIP
/// push (which names only the notification), CallKit shows the system's
/// incoming-call screen at once (as "Ortus", as Apple requires), and the
/// caller's name follows once the text is fetched with the phone's fetch
/// token. Answer opens the call in its room.
@MainActor
final class Ringer: NSObject {
    static let shared = Ringer()

    private let registry = PKPushRegistry(queue: .main)
    private let provider: CXProvider
    private let controller = CXCallController()
    /// Each ringing call's room.
    private var rooms: [UUID: (room: String, title: String)] = [:]
    /// The phone's VoIP token, once PushKit gives it.
    private(set) var voipToken: Data?

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    /// Starts listening for calls (after sign-in, on a phone).
    func start() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    /// The call is over on the screen: CallKit forgets it too.
    func endAll() {
        for id in rooms.keys {
            controller.request(CXTransaction(action: CXEndCallAction(call: id))) { _ in }
        }
        rooms.removeAll()
    }
}

extension Ringer: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token
        Task { @MainActor in
            self.voipToken = token
            await AppDelegate.model?.registerVoip(token)
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let info = payload.dictionaryPayload
        // Reported to CallKit at once (Apple ends an app that does not).
        let id = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "Ortus")
        update.localizedCallerName = "Ortus"
        update.hasVideo = true
        provider.reportNewIncomingCall(with: id, update: update) { _ in completion() }
        guard let (notification, server) = Push.parts(of: info), let registration = PushStore.load(server: server) else { return }
        Task { @MainActor in
            guard let notice = try? await Push.fetch(server: server, fetchToken: registration.fetch_token, id: notification),
                  let room = Push.callRoom(notice.path) else { return }
            self.rooms[id] = (room, notice.title)
            let named = CXCallUpdate()
            named.localizedCallerName = notice.title
            self.provider.reportCall(with: id, updated: named)
        }
    }
}

extension Ringer: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in self.rooms.removeAll() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let id = action.callUUID
        Task { @MainActor in
            if let call = self.rooms[id] { AppDelegate.model?.answered = AnsweredCall(room: call.room, title: call.title) }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        Task { @MainActor in
            self.rooms[id] = nil
            action.fulfill()
        }
    }
}

/// A call answered from the system's call screen.
struct AnsweredCall: Identifiable, Equatable {
    let room: String
    let title: String
    var id: String { room }
}
