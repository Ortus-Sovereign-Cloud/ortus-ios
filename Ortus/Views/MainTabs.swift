import SwiftUI

/// The tab bar: Mail, Chat, Calendar, Drive, More (the sections named as
/// on the web); search and the bell at the top of each.
struct MainTabs: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 0) {
            if model.offline || model.waiting > 0 {
                Label(model.waiting > 0 ? "offline.waiting \(model.waiting)" : "offline.banner", systemImage: model.offline ? "wifi.slash" : "arrow.up.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.surface)
                    .accessibilityIdentifier("offline")
                    .onAppear {
                        let said = model.waiting > 0 ? String(localized: "offline.waiting \(model.waiting)") : String(localized: "offline.banner")
                        AccessibilityNotification.Announcement(said).post()
                    }
            }
        TabView(selection: $model.tab) {
            InboxView().tabItem { Label("app.mail", systemImage: "tray") }.tag(0)
            ChatsView().tabItem { Label("app.chat", systemImage: "bubble.left") }.tag(1)
            CalendarView().tabItem { Label("app.calendar", systemImage: "calendar") }.tag(2)
            DriveView().tabItem { Label("app.drive", systemImage: "folder") }.tag(3)
            MoreView().tabItem { Label("tab.more", systemImage: "square.grid.2x2") }.tag(4)
        }
        }
        // The bell's number: on opening and whenever the app comes back.
        .task { await model.refreshUnread() }
        .onChange(of: phase) {
            if phase == .active { Task { await model.refreshUnread() } }
        }
        // A call answered on the lock screen opens here.
        .fullScreenCover(item: $model.answered, onDismiss: { Ringer.shared.endAll() }) { call in
            CallView(room: call.room, title: call.title)
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
            .topBar()
        }
    }
}
