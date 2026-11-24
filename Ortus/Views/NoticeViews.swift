import OrtusKit
import SwiftUI

/// MobileNotifications: alerts, approvals, mentions and updates, newest
/// first, each opening what it is about; all marked read on opening.
struct NotificationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var items: [Notice] = []
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        List {
            ListStatus(failure: failure, isEmpty: loaded && items.isEmpty, empty: "notify.empty") { await load() }
            ForEach(items) { n in
                PlaceLink(place: Place(path: n.path ?? "/" + n.app)) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(n.kind)).foregroundStyle(n.kind == "alert" ? .red : Theme.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.title).font(.body.weight(n.read ? .regular : .semibold)).foregroundStyle(Theme.text)
                            if let d = n.detail, !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(Theme.text2) }
                            Text(n.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.text2)
                        }
                    }
                }
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("notify.title")
        .opensPlaces()
        .refreshable { await load() }
        .task {
            await load()
            if failure == nil {
                // Read now, even when the list closes at once: the bell's
                // number goes.
                Task {
                    try? await model.client?.markNoticesRead()
                    await model.refreshUnread()
                }
            }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            items = try await client.notices()
            failure = nil
            loaded = true
        } catch {
            failure = model.listFailure(error, showing: !items.isEmpty)
        }
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "alert": "exclamationmark.triangle.fill"
        case "approval": "checkmark.seal"
        case "mention": "at"
        default: "bell"
        }
    }
}

/// MobileSearch: mail, files, events and people at once; a result opens
/// what it found, where the web would open it.
struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var words = ""
    @State private var hits: [SearchHit] = []
    @State private var failure: String?
    @State private var searched = false

    var body: some View {
        List {
            ListStatus(failure: failure, isEmpty: searched && hits.isEmpty, empty: "search.none") { await search() }
            ForEach(hits, id: \.key) { h in
                PlaceLink(place: h.place) {
                    VStack(alignment: .leading, spacing: 2) {
                        // A chat message's title is its room (none for a direct one).
                        Text(h.title.isEmpty ? (h.meta?.from ?? "") : h.title).foregroundStyle(Theme.text)
                        if let s = h.snippet, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(Theme.text2).lineLimit(2) }
                        Text(appName(h.app)).font(.caption).foregroundStyle(Theme.accent)
                    }
                }
                .accessibilityIdentifier("hit-" + h.app)
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $words, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("search.prompt"))
        .onSubmit(of: .search) { Task { await search() } }
        // As the web does: results while typing, once the typing pauses.
        .task(id: words) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled, !words.trimmingCharacters(in: .whitespaces).isEmpty { await search() }
        }
        .navigationTitle("search.title")
        .opensPlaces()
    }

    /// An app's name as the web names it ("drive" is Drive).
    private func appName(_ app: String) -> String {
        let key = "app." + app
        let name = String(localized: String.LocalizationValue(stringLiteral: key))
        return name == key ? app : name
    }

    private func search() async {
        guard let client = model.client else { return }
        do {
            hits = try await client.search(words)
            failure = nil
            searched = true
        } catch {
            hits = []
            searched = false
            failure = model.listFailure(error, showing: false)
        }
    }
}
