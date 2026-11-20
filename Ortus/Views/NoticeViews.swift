import OrtusKit
import SwiftUI

/// MobileNotifications: alerts, approvals, mentions and updates, newest
/// first; all marked read on opening.
struct NotificationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var items: [Notice] = []

    var body: some View {
        List(items) { n in
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("notify.title")
        .task {
            items = (try? await model.client?.notices()) ?? []
            try? await model.client?.markNoticesRead()
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

/// MobileSearch: mail, files, events and people at once.
struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var words = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        List(hits, id: \.key) { h in
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).foregroundStyle(Theme.text)
                if let s = h.snippet { Text(s).font(.subheadline).foregroundStyle(Theme.text2).lineLimit(2) }
                Text(h.app).font(.caption).foregroundStyle(Theme.accent)
            }
            .listRowBackground(Theme.background)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $words, prompt: Text("search.prompt"))
        .onSubmit(of: .search) { Task { hits = (try? await model.client?.search(words)) ?? [] } }
        .navigationTitle("search.title")
    }
}
