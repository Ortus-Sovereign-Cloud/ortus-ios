// swift-tools-version: 5.9
// Google's WebRTC (BSD-3-Clause), the one library in the app that is not
// ours: native calls, allowed by the owner 2026-11-22. The xcframework as
// webrtc-sdk builds it (Google publishes none), release 150.7871.04 of
// 2026-10-23, pinned by its SHA-256 (which SwiftPM checks on download).
import PackageDescription

let package = Package(
    name: "WebRTC",
    platforms: [.iOS(.v13)],
    products: [.library(name: "WebRTC", targets: ["WebRTC"])],
    targets: [
        .binaryTarget(
            name: "WebRTC",
            url: "https://github.com/webrtc-sdk/Specs/releases/download/150.7871.04/WebRTC.xcframework.zip",
            checksum: "9532fe3ce47507c304f37a4355b907be1e89967971d614a04603005a546249be"
        ),
    ]
)
