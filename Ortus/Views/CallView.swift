import AVKit
import OrtusKit
import SwiftUI
import WebRTC

/// MobileCall: a room's call, natively (Google's WebRTC), on the same media
/// server as the web client. Mute, camera, speaker and leave; the screen
/// stays on while the call lasts; leaving ends it on the server at once.
struct CallView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let room: Room
    let title: String

    var body: some View {
        NavigationStack {
            Group {
                if let client = model.client {
                    CallScreen(call: NativeCall(client: client, room: room.id), leave: { dismiss() })
                } else {
                    Text("error.generic").foregroundStyle(Theme.text2)
                }
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("call.close") { dismiss() } }
            }
        }
    }
}

private struct CallScreen: View {
    @StateObject var call: NativeCall
    let leave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let error = call.error {
                Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("callError")
            }
            Text(call.connected ? "call.connected" : call.answered ? "call.connecting" : "call.joining")
                .font(.footnote).foregroundStyle(Theme.text2)
                .accessibilityIdentifier(call.answered ? "answered" : "joining")
            ZStack(alignment: .bottomTrailing) {
                if call.remotes.isEmpty {
                    Text("call.alone").foregroundStyle(Theme.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let columns = call.remotes.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(call.remotes) { r in
                                Tile(name: r.name, track: r.video, mirror: false, pip: r.id == call.remotes.first(where: { $0.video != nil })?.id)
                                    .aspectRatio(call.remotes.count == 1 ? 0.75 : 1, contentMode: .fit)
                            }
                        }
                    }
                }
                if let local = call.local, call.camera {
                    Tile(name: nil, track: local, mirror: true, pip: false).frame(width: 96, height: 128).padding(8)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 12) {
                control(call.muted ? "call.unmute" : "call.mute", on: call.muted, id: "mute") { call.toggleMute() }
                control(call.camera ? "call.cameraOff" : "call.cameraOn", on: !call.camera, id: "camera") { call.toggleCamera() }
                control(call.speaker ? "call.earpiece" : "call.speaker", on: false, id: "speaker") { call.toggleSpeaker() }
                if call.camera { control("call.flip", on: false, id: "flip") { call.flipCamera() } }
                Button(role: .destructive, action: leave) {
                    Text("call.hangUp").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(red: 0.9, green: 0.28, blue: 0.3), in: Capsule())
                }
                .accessibilityIdentifier("hangUp")
            }
            .padding(.bottom, 8)
        }
        .padding(12)
        .onAppear { call.start() }
        .onDisappear { call.end() }
    }

    private func control(_ label: LocalizedStringKey, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(on ? Theme.surface2 : Theme.surface, in: Capsule())
        }
        .accessibilityIdentifier(id)
    }
}

/// One person's video, or their name when they show none.
private struct Tile: View {
    let name: String?
    let track: RTCVideoTrack?
    let mirror: Bool
    let pip: Bool

    var body: some View {
        ZStack(alignment: track == nil ? .center : .bottomLeading) {
            Theme.surface2
            if let track { Video(track: track, mirror: mirror, pip: pip) }
            if let name { Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).padding(8) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct Video: UIViewRepresentable {
    let track: RTCVideoTrack
    let mirror: Bool
    /// This tile's video goes on in a small window when the app is left.
    let pip: Bool

    final class Coordinator { var pip: AVPictureInPictureController? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let v = RTCMTLVideoView()
        v.videoContentMode = .scaleAspectFill
        if mirror { v.transform = CGAffineTransform(scaleX: -1, y: 1) }
        track.add(v)
        if pip, AVPictureInPictureController.isPictureInPictureSupported() {
            let small = AVPictureInPictureVideoCallViewController()
            small.preferredContentSize = CGSize(width: 360, height: 480)
            let video = RTCMTLVideoView(frame: small.view.bounds)
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            video.videoContentMode = .scaleAspectFill
            small.view.addSubview(video)
            track.add(video)
            let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: v, contentViewController: small)
            let controller = AVPictureInPictureController(contentSource: source)
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            context.coordinator.pip = controller
        }
        return v
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {}

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.pip?.stopPictureInPicture()
        coordinator.pip = nil
    }
}
