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
