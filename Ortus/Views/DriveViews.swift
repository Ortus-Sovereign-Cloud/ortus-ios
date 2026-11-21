import OrtusKit
import SwiftUI

/// MobileDrive: one's folders and files; a file's share sheet.
struct DriveView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            FolderView(parent: nil, title: String(localized: "tab.files"))
                .navigationDestination(for: DriveItem.self) { item in
                    if item.isFolder {
                        FolderView(parent: item.id, title: item.name)
                    } else if item.mime == "application/vnd.ortus.doc" {
                        DocView(doc: item.id)
                    } else {
                        ShareView(item: item)
                    }
                }
        }
    }
}

struct FolderView: View {
    @EnvironmentObject var model: AppModel
    let parent: String?
    let title: String
    @State private var items: [DriveItem] = []

    var body: some View {
        List(items) { item in
            NavigationLink(value: item) {
                HStack(spacing: 12) {
                    Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                        .foregroundStyle(item.isFolder ? Theme.accent : Theme.text2).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(Theme.text).lineLimit(1)
                        HStack(spacing: 6) {
                            if let d = item.modified { Text(d.formatted(.dateTime.day().month(.abbreviated))) }
                            if !item.isFolder, let size = item.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                        }
                        .font(.caption).foregroundStyle(Theme.text2)
                    }
                    if let label = item.label {
                        Spacer()
                        Text(label).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .listRowBackground(Theme.background)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        items = (try? await model.client?.folder(parent))?.items ?? []
    }
}

/// MobileShare: who has the file, its link, sharing with someone.
struct ShareView: View {
    @EnvironmentObject var model: AppModel
    let item: DriveItem
    @State private var shares: Shares?
    @State private var email = ""
    @State private var note: String?

    var body: some View {
        List {
            Section("share.title") {
                ForEach((shares?.people ?? []) + (shares?.outside ?? [])) { h in
                    HStack {
                        Text(initials(h.name ?? h.email ?? "")).font(.caption.bold()).foregroundStyle(Theme.background)
                            .frame(width: 32, height: 32).background(Theme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        Text(h.name ?? h.email ?? "").foregroundStyle(Theme.text)
                        Spacer()
                        Text(h.role ?? "").font(.caption).foregroundStyle(Theme.text2)
                    }
                }
                HStack {
                    TextField("share.address", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        .accessibilityIdentifier("shareWith")
                    Button("share.add") { Task { await add() } }.disabled(!email.contains("@"))
                }
            }
            Section("share.link") {
                if let url = shares?.link?.url {
                    Text(url).font(.footnote.monospaced()).foregroundStyle(Theme.accent).lineLimit(1)
                    if let until = shares?.link?.expiresAt {
                        Text("share.until \(Date(timeIntervalSince1970: Double(until) / 1000).formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("share.copy") { UIPasteboard.general.string = url; note = String(localized: "share.copied") }
                } else {
                    Button("share.makeLink") { Task { await link() } }
                }
            }
            if let note { Text(note).foregroundStyle(Theme.text2).accessibilityIdentifier("note") }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async { shares = try? await model.client?.shares(item) }

    private func add() async {
        do {
            try await model.client?.share(item, with: email.trimmingCharacters(in: .whitespaces), role: "view")
            email = ""
            await load()
        } catch {
            note = model.say(error)
        }
    }

    private func link() async {
        do {
            shares = try await model.client?.makeLink(item)
            await load()
        } catch {
            note = model.say(error)
        }
    }
}
