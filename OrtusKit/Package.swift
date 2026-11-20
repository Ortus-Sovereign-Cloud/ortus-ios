// swift-tools-version: 5.10
// What the Ortus phone app does that does not need a screen: the API
// client, the passkey encoding (WebAuthn) and the models. Built and tested
// on Linux as well as on Apple platforms.
import PackageDescription

let package = Package(
    name: "OrtusKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OrtusKit", targets: ["OrtusKit"])],
    targets: [
        .target(name: "OrtusKit"),
        .testTarget(name: "OrtusKitTests", dependencies: ["OrtusKit"]),
    ]
)
