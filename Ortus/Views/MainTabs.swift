import SwiftUI

/// The tab bar: Mail, Chat, Calendar, Files, More.
struct MainTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            InboxView().tabItem { Label("tab.mail", systemImage: "tray") }.tag(0)
            ChatsView().tabItem { Label("tab.chat", systemImage: "bubble.left") }.tag(1)
            CalendarView().tabItem { Label("tab.calendar", systemImage: "calendar") }.tag(2)
            DriveView().tabItem { Label("tab.files", systemImage: "folder") }.tag(3)
            MoreView().tabItem { Label("tab.more", systemImage: "square.grid.2x2") }.tag(4)
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
                    NavigationLink { ForYouView() } label: { Label("foryou.title", systemImage: "checkmark.seal") }.accessibilityIdentifier("foryou")
                    NavigationLink { NotificationsView() } label: { Label("notify.title", systemImage: "bell") }
                    NavigationLink { SearchView() } label: { Label("search.title", systemImage: "magnifyingglass") }
                    if model.me?.role == "admin" || model.me?.role == "owner" {
                        NavigationLink { AdminView() } label: { Label("admin.title", systemImage: "shield") }.accessibilityIdentifier("admin")
                    }
                }
                Section {
                    Button("more.signOut", role: .destructive) { Task { await model.signOut() } }.accessibilityIdentifier("signOut")
                }
            }
            .navigationTitle("tab.more")
        }
    }
}
