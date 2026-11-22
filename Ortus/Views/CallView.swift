import OrtusKit
import SwiftUI
import WebKit

/// MobileCall: a room's call, as the web client has it (the same media
/// server), in a web view signed in with the app's session. The camera and
/// microphone are allowed for the installation's own page only; leaving
/// the call (or going anywhere but /calls) closes the screen.
struct CallView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let room: Room
    let title: String

    var body: some View {
        NavigationStack {
            Group {
                if let client = model.client, let token = client.token {
                    CallPage(server: client.server, token: token, room: room.id, leave: { dismiss() })
                        .ignoresSafeArea(edges: .bottom)
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

private struct CallPage: UIViewRepresentable {
    let server: URL
    let token: String
    let room: String
    let leave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(server: server, leave: leave) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Its own store: the session is this view's only.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = UIColor(Theme.background)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.accessibilityIdentifier = "call"
        var url = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        url.path = "/calls"
        url.queryItems = [URLQueryItem(name: "room", value: room)]
        let secure = server.scheme == "https"
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: secure ? "__Host-ortus" : "ortus",
            .value: token,
            .path: "/",
            .domain: server.host ?? "",
        ]
        if secure { props[.secure] = "TRUE" }
        if let cookie = HTTPCookie(properties: props), let target = url.url {
            config.websiteDataStore.httpCookieStore.setCookie(cookie) { view.load(URLRequest(url: target)) }
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let server: URL
        let leave: () -> Void
        init(server: URL, leave: @escaping () -> Void) {
            self.server = server
            self.leave = leave
        }

        /// The camera and microphone, for the installation's own page only.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let ours = origin.host == server.host && origin.protocol == server.scheme
            decisionHandler(ours ? .grant : .deny)
        }

        /// Only the call: leaving it (the page goes to the channel) closes the
        /// screen; nothing else opens in here.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.host == server.host, url.path == "/calls" || url.path.hasPrefix("/assets/") || url.path.hasPrefix("/api/") {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.leave() }
        }
    }
}
