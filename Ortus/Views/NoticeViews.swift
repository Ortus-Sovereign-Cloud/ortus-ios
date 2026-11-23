import OrtusKit
import SwiftUI

/// MobileNotifications: alerts, approvals, mentions and updates, newest
/// first; all marked read on opening.
struct NotificationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var items: [Notice] = []
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        List {
            ListStatus(failure: failure, isEmpty: loaded && items.isEmpty, empty: "notify.empty") { await load() }
            ForEach(items) { n in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(n.kind)).foregroundStyle(n.kind == "alert" ? .red : Theme.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.body.weight(n.read ? .regular : .semibold)).foregroundStyle(Theme.text)
                        if let d = n.detail, !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(Theme.text2) }
                        Text(n.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.text2)
                    }
                }
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("notify.title")
        .refreshable { await load() }
        .task {
            await load()
            if failure == nil { try? await model.client?.markNoticesRead() }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            items = try await client.notices()
            failure = nil
        } catch {
            failure = model.listFailure(error, showing: !items.isEmpty)
        }
        loaded = true
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

/// MobileSearch: mail, files, events and people at once.
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.title).foregroundStyle(Theme.text)
                    if let s = h.snippet { Text(s).font(.subheadline).foregroundStyle(Theme.text2).lineLimit(2) }
                    Text(h.app).font(.caption).foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $words, prompt: Text("search.prompt"))
        .onSubmit(of: .search) { Task { await search() } }
        .navigationTitle("search.title")
    }

    private func search() async {
        guard let client = model.client else { return }
        do {
            hits = try await client.search(words)
            failure = nil
        } catch {
            hits = []
            failure = model.listFailure(error, showing: false)
        }
        searched = true
    }
}
