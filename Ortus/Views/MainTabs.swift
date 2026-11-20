import SwiftUI

/// The tab bar: Mail, Chat, Calendar, Files, More.
struct MainTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            InboxView().tabItem { Label("tab.mail", systemImage: "tray") }
            ChatsView().tabItem { Label("tab.chat", systemImage: "bubble.left") }
            CalendarView().tabItem { Label("tab.calendar", systemImage: "calendar") }
            Placeholder(title: "tab.files").tabItem { Label("tab.files", systemImage: "folder") }
            MoreView().tabItem { Label("tab.more", systemImage: "square.grid.2x2") }
        }
    }
}

struct Placeholder: View {
    let title: LocalizedStringKey
    var body: some View {
        NavigationStack {
            Color.clear.background(Theme.background).navigationTitle(title)
        }
    }
}

/// MobileMore: every app, and signing out.
struct MoreView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    Section {
                        VStack(alignment: .leading) {
                            Text(me.name).font(.headline)
                            Text(me.email).font(.subheadline).foregroundStyle(Theme.text2)
                        }
                        .accessibilityIdentifier("me")
                    }
                }
                Section {
                    Button("more.signOut", role: .destructive) { model.signOut() }
                }
            }
            .navigationTitle("tab.more")
        }
    }
}
