import AVFoundation
import Foundation
import OrtusKit
import UIKit
import WebRTC

/// One other person in the call: their session, name, and video if they show it.
struct Remote: Identifiable {
    let id: String
    let name: String
    let video: RTCVideoTrack?
}

/// A call in a room, natively (Google's WebRTC), with the web client's
/// signalling (see OrtusKit's Calls). Media goes to the installation's
/// media node, or through its TURN relay where only web ports get through.
@MainActor
final class NativeCall: NSObject, ObservableObject {
    @Published private(set) var answered = false
    @Published private(set) var connected = false
    @Published var error: String?
    @Published private(set) var muted = false
    @Published private(set) var camera = true
    @Published private(set) var speaker = true
    @Published private(set) var remotes: [Remote] = []
    @Published private(set) var local: RTCVideoTrack?

    private let client: Client
    private let room: String
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()
    private var pc: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var capturer: RTCCameraVideoCapturer?
    private var audioTrack: RTCAudioTrack?
    private var session: String?
    private var info: CallInfo?
    private var videos: [String: RTCVideoTrack] = [:]
    private let joiner = CallParts.Joiner()
    private var reporting: Task<Void, Never>?

    init(client: Client, room: String) {
        self.client = client
        self.room = room
    }

    func start() {
        Task {
            do {
                configureAudio()
                let f = Self.factory
                let none = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                audioTrack = f.audioTrack(with: f.audioSource(with: none), trackId: "ortus-audio")
                local = startCamera()
                camera = local != nil
                let joined = try await client.joinCall(room: room)
                session = joined.session
                info = joined.call
                try await connect(joined.ice_servers ?? [])
                // The session stays while reported; others' names come back.
                reporting = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        guard let self, let s = self.session else { return }
                        if let now = try? await self.client.callState(session: s, muted: self.muted, camera: self.camera) {
                            self.info = now
                            self.refresh()
                        }
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func configureAudio() {
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        try? audio.setCategory(.playAndRecord, with: [.allowBluetooth, .defaultToSpeaker])
        try? audio.setMode(.videoChat)
        try? audio.setActive(true)
        audio.unlockForConfiguration()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func startCamera() -> RTCVideoTrack? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == .front }) ?? devices.first else { return nil }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        // About 640 wide: enough for a phone's tile, kind to the network.
        let format = formats.min { a, b in
            abs(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width - 640) < abs(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width - 640)
        }
        guard let format else { return nil }
        let source = Self.factory.videoSource()
        let cap = RTCCameraVideoCapturer(delegate: source)
        cap.startCapture(with: device, format: format, fps: 24)
        capturer = cap
        return Self.factory.videoTrack(with: source, trackId: "ortus-camera")
        #endif
    }

    private func connect(_ servers: [IceServer]) async throws {
        let config = RTCConfiguration()
        config.iceServers = servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        config.sdpSemantics = .unifiedPlan
        let none = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = Self.factory.peerConnection(with: config, constraints: none, delegate: self) else { throw CallError.noConnection }
        pc = peer
        let dc = peer.dataChannel(forLabel: "signalling", configuration: RTCDataChannelConfiguration())
        dc?.delegate = self
        channel = dc
        let send = RTCRtpTransceiverInit()
        send.direction = .sendOnly
        send.streamIds = ["ortus-local"]
        let bare = RTCRtpTransceiverInit()
        bare.direction = .sendOnly
        if let audioTrack { peer.addTransceiver(with: audioTrack, init: send) } else { peer.addTransceiver(of: .audio, init: bare) }
        if let local { peer.addTransceiver(with: local, init: send) } else { peer.addTransceiver(of: .video, init: bare) }
        // The screen (not shared from the phone).
        peer.addTransceiver(of: .video, init: bare)
        let offer = try await peer.offerAsync(none)
        try await peer.setLocalAsync(offer)
        guard let session else { throw CallError.noConnection }
        let answer = try await client.sendOffer(session: session, sdp: offer.sdp)
        try await peer.setRemoteAsync(RTCSessionDescription(type: .answer, sdp: answer))
        answered = true
    }

    /// The node offers others' tracks (or stops them); we answer over the channel.
    private func signal(_ message: String) async {
        guard let peer = pc, let (sdp, n) = CallParts.offer(message) else { return }
        do {
            try await peer.setRemoteAsync(RTCSessionDescription(type: .offer, sdp: sdp))
            let answer = try await peer.answerAsync(RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            try await peer.setLocalAsync(answer)
            for part in CallParts.split(CallParts.answer(answer.sdp, n: n)) {
                channel?.sendData(RTCDataBuffer(data: Data(part.utf8), isBinary: false))
            }
        } catch {}
    }

    /// Everyone else, by name, with their video where there is one.
    private func refresh(_ extra: String? = nil) {
        let me = session
        var all = (info?.sessions.map(\.session) ?? []) + [extra].compactMap { $0 } + Array(videos.keys)
        var seen = Set<String>()
        all = all.filter { $0 != me && seen.insert($0).inserted }
        remotes = all.map { Remote(id: $0, name: info?.name(of: $0) ?? "…", video: videos[$0]) }
    }

    func toggleMute() {
        muted.toggle()
        audioTrack?.isEnabled = !muted
        report()
    }

    func toggleCamera() {
        guard let local else { return }
        camera.toggle()
        local.isEnabled = camera
        report()
    }

    func toggleSpeaker() {
        speaker.toggle()
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        try? audio.overrideOutputAudioPort(speaker ? .speaker : .none)
        audio.unlockForConfiguration()
    }

    private func report() {
        guard let s = session else { return }
        let (m, c) = (muted, camera)
        Task { _ = try? await client.callState(session: s, muted: m, camera: c) }
    }

    /// Leaves the call (the node drops this session at once) and lets go of everything.
    func end() {
        reporting?.cancel()
        if let s = session {
            let client = client
            Task.detached { try? await client.leaveCall(session: s) }
        }
        session = nil
        capturer?.stopCapture()
        channel?.close()
        pc?.close()
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        try? audio.setActive(false)
        audio.unlockForConfiguration()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    enum CallError: LocalizedError {
        case noConnection
        var errorDescription: String? { String(localized: "error.generic") }
    }
}

extension NativeCall: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor in self.connected = newState == .connected }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let who = mediaStreams.first?.streamId else { return }
        let track = rtpReceiver.track as? RTCVideoTrack
        Task { @MainActor in
            if let track { self.videos[who] = track }
            self.refresh(who)
        }
    }
}

extension NativeCall: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let text = String(decoding: buffer.data, as: UTF8.self)
        Task { @MainActor in
            guard let whole = self.joiner.take(text) else { return }
            await self.signal(whole)
        }
    }
}

/// libwebrtc's callbacks as async calls.
extension RTCPeerConnection {
    func offerAsync(_ c: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { k in
            offer(for: c) { sdp, error in
                if let sdp { k.resume(returning: sdp) } else { k.resume(throwing: error ?? NativeCall.CallError.noConnection) }
            }
        }
    }

    func answerAsync(_ c: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { k in
            answer(for: c) { sdp, error in
                if let sdp { k.resume(returning: sdp) } else { k.resume(throwing: error ?? NativeCall.CallError.noConnection) }
            }
        }
    }

    func setLocalAsync(_ d: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            setLocalDescription(d) { error in if let error { k.resume(throwing: error) } else { k.resume() } }
        }
    }

    func setRemoteAsync(_ d: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            setRemoteDescription(d) { error in if let error { k.resume(throwing: error) } else { k.resume() } }
        }
    }
}
