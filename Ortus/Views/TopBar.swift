import OrtusKit
import SafariServices
import SwiftUI

extension View {
    /// Search and the bell at the top of a tab, as on the web's top bar.
    func topBar() -> some View { modifier(TopBar()) }
}

private struct TopBar: ViewModifier {
    @EnvironmentObject var model: AppModel
    @State private var open: Sheet?

    enum Sheet: Identifiable {
        case search, notices
        var id: Self { self }
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { open = .search } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel(Text("search.title"))
                        .accessibilityIdentifier("search")
                    Button { open = .notices } label: {
                        Image(systemName: "bell")
                            .overlay(alignment: .topTrailing) {
                                if model.unread > 0 {
                                    Text(model.unread > 99 ? "99+" : model.unread.formatted())
                                        .font(.caption2.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color(red: 1, green: 0.48, blue: 0.43), in: Capsule())
                                        .fixedSize()
                                        .offset(x: 10, y: -8)
                                }
                            }
                    }
                    .accessibilityLabel(Text("notify.title"))
                    // The number for VoiceOver (and the tests), as the badge shows it.
                    .accessibilityValue(model.unread > 0 ? model.unread.formatted() : "")
                    .accessibilityIdentifier("bell")
                }
            }
            .sheet(item: $open) { sheet in
                NavigationStack {
                    Group {
                        switch sheet {
                        case .search: SearchView()
                        case .notices: NotificationsView()
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("sheet.close") { open = nil }.accessibilityIdentifier("closeSheet")
                        }
                    }
                }
                .environmentObject(model)
            }
    }
}

/// A row that opens its place: one of the app's screens, or the web page
/// in Safari inside the app for what the phone has no screen for.
struct PlaceLink<Label: View>: View {
    @EnvironmentObject var model: AppModel
    let place: Place
    let label: () -> Label
    @State private var web: WebAddress?

    init(place: Place, @ViewBuilder label: @escaping () -> Label) {
        self.place = place
        self.label = label
    }

    var body: some View {
        if case .web = place {
            Button { web = model.client.flatMap { place.webURL(on: $0.server) }.map(WebAddress.init) } label: { label() }
                .foregroundStyle(Theme.text)
                .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
        } else {
            NavigationLink(value: place) { label() }
        }
    }
}

struct WebAddress: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// The screen of a place (`.web` is opened by `PlaceLink`).
struct PlaceView: View {
    let place: Place

    var body: some View {
        switch place {
        case let .thread(id): ThreadView(threadID: id)
        case let .room(id): RoomView(id: id)
        case let .doc(id): DocView(doc: id)
        // A folder too: its name comes with it.
        case let .folder(id), let .file(id): FileView(id: id)
        case let .event(id, start): EventView(id: id, start: start)
        case .approvals: ForYouView()
        case .web: EmptyView()
        }
    }
}

extension View {
    /// Rows of places (search results, notifications) open here.
    func opensPlaces() -> some View {
        navigationDestination(for: Place.self) { PlaceView(place: $0) }
    }
}

/// A chat room by its id (a search result names only that).
private struct RoomView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    @State private var rooms: Rooms?
    @State private var failure: String?

    var body: some View {
        if let rooms, let room = rooms.rooms.first(where: { $0.id == id }) {
            ChannelView(room: room, title: rooms.title(room))
        } else {
            List { ListStatus(failure: failure, isEmpty: rooms != nil, empty: "search.gone") { await load() } }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .task { await load() }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            rooms = try await client.rooms()
            failure = nil
        } catch {
            failure = model.listFailure(error, showing: false)
        }
    }
}

/// A file or folder by its id: a folder opens, a document to read, any
/// other file to share.
private struct FileView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    @State private var item: DriveItem?
    @State private var failure: String?

    var body: some View {
        if let item {
            if item.isFolder {
                FolderView(parent: item.id, title: item.name)
            } else if item.mime == "application/vnd.ortus.doc" {
                DocView(doc: item.id)
            } else {
                ShareView(item: item)
            }
        } else {
            List { ListStatus(failure: failure, isEmpty: false, empty: "search.gone") { await load() } }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .task { await load() }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            item = try await client.item(id)
            failure = nil
        } catch {
            failure = model.listFailure(error, showing: false)
        }
    }
}

/// An event on its day, to see and answer.
private struct EventView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let start: Int64
    @State private var events: [Event]?
    @State private var failure: String?

    private var day: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(start) / 1000)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline).foregroundStyle(Theme.text2)
                if let failure {
                    Text(failure).foregroundStyle(.red)
                    Button("list.tryAgain") { Task { await load() } }.buttonStyle(.bordered)
                }
                // The event itself; a repeat's (whose id may differ) is
                // among the day's.
                let shown = (events ?? []).filter { $0.id == id }
                ForEach(shown.isEmpty ? events ?? [] : shown) { e in EventCard(event: e) { await answer(e, $0) } }
                if events?.isEmpty == true { Text("search.gone").foregroundStyle(Theme.text2) }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let client = model.client else { return }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        do {
            events = try await client.events(from: day, to: end)
            failure = nil
        } catch {
            failure = model.listFailure(error, showing: false)
        }
    }

    private func answer(_ e: Event, _ a: String) async {
        try? await model.client?.answer(e, a)
        await load()
    }
}
