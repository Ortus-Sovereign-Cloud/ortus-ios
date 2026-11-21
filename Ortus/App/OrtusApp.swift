import SwiftUI

@main
struct OrtusApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Root()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // The app's own link, from an invitation page on this phone.
                .onOpenURL { model.open($0.absoluteString) }
                // An invitation link (universal link) for a domain the app names.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.open(url.absoluteString) }
                }
        }
    }
}

struct Root: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.stage {
        case .join: JoinView()
        case .welcome: WelcomeView()
        case .signedIn: MainTabs()
        }
    }
}
