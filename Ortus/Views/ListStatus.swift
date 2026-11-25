import SwiftUI

/// What a list says above its rows: that it could not be loaded (with a
/// way to try again), or that there is nothing in it. A failure never
/// looks like an empty list.
struct ListStatus: View {
    let failure: String?
    let isEmpty: Bool
    let empty: LocalizedStringKey
    let retry: () async -> Void

    var body: some View {
        if let failure {
            VStack(alignment: .leading, spacing: 8) {
                Text(failure).foregroundStyle(.red)
                Button("list.tryAgain") { Task { await retry() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("tryAgain")
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("listFailed")
            // VoiceOver says it when it appears, not only when it is reached.
            .onAppear { AccessibilityNotification.Announcement(failure).post() }
        } else if isEmpty {
            Text(empty).foregroundStyle(Theme.text2)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("listEmpty")
        }
    }
}

extension AppModel {
    /// What a list says about a failed load, if anything: nothing when the
    /// load was only cancelled, and nothing when the phone is offline and
    /// shows what it kept (the offline banner says so).
    func listFailure(_ error: Error, showing: Bool) -> String? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        if showing && (offline || error is URLError) { return nil }
        return say(error)
    }
}
