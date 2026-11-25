import OrtusKit
import SwiftUI

/// MobileChats: rooms newest first, all or only unread, partner rooms
/// marked External.
struct ChatsView: View {
    @EnvironmentObject var model: AppModel
    @State private var data: Rooms?
    @State private var onlyUnread = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        filter("chat.all", selected: !onlyUnread) { onlyUnread = false }
                        let n = data?.rooms.filter { ($0.unread ?? 0) > 0 }.count ?? 0
                        filter("chat.unread \(n)", selected: onlyUnread) { onlyUnread = true }
                    }
                    .listRowBackground(Color.clear)
                }
                ListStatus(failure: failure, isEmpty: data != nil && shown.isEmpty, empty: onlyUnread ? "chat.noUnread" : "chat.noRooms") { await load() }
                ForEach(shown) { room in
                    NavigationLink(value: room) {
                        HStack(spacing: 12) {
                            Text(room.kind == "direct" ? initials(data?.title(room) ?? "") : "#")
                                .font(.footnote.bold()).foregroundStyle(room.kind == "direct" ? Theme.background : Theme.text)
                                .frame(width: 40, height: 40)
                                .background(room.kind == "direct" ? Theme.accent.opacity(0.85) : Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(data?.title(room) ?? room.name).font(.body.bold()).foregroundStyle(Theme.text).lineLimit(1)
                                    if room.federated == true {
                                        Text("chat.external").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                            .foregroundStyle(.orange).background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                if let topic = room.topic, !topic.isEmpty {
                                    Text(topic).font(.subheadline).foregroundStyle(Theme.text2).lineLimit(1)
                                }
                            }
                            Spacer()
                            if let n = room.unread, n > 0 {
                                Text(n.formatted()).font(.caption.bold()).foregroundStyle(Theme.background)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.accent, in: Capsule())
                            }
                        }
                    }
                    .listRowBackground(Theme.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("app.chat")
            .topBar()
            .navigationDestination(for: Room.self) { ChannelView(room: $0, title: data?.title($0) ?? $0.name) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private var shown: [Room] {
        (data?.rooms ?? []).filter { $0.state != "invite" || true }.filter { !onlyUnread || ($0.unread ?? 0) > 0 }
    }

    private func filter(_ label: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? Theme.background : Theme.text)
                .background(selected ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            try await quickly({ try await client.rooms() }) { data = $0; if let me = $0.me { model.chatMe = me } }
            failure = nil
        } catch {
            failure = model.listFailure(error, showing: !(data?.rooms.isEmpty ?? true))
        }
    }
}

/// MobileChannel: the messages of a room and a message box.
struct ChannelView: View {
    @EnvironmentObject var model: AppModel
    let room: Room
    let title: String
    @State private var messages: Messages?
    @State private var text = ""
    @State private var note: String?
    @State private var calling = false

    var body: some View {
        // End-to-end rooms are opened and sealed on the phone (EndToEnd).
        if room.encrypted == true {
            SealedChannelView(room: room, title: title)
        } else {
            channel
        }
    }

    private var channel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(messages?.messages.filter { $0.deleted != true && $0.thread == nil } ?? []) { m in
                            HStack(alignment: .top, spacing: 10) {
                                let name = messages?.people[m.sender]?.name ?? m.sender
                                Text(initials(name)).font(.caption.bold()).foregroundStyle(Theme.background)
                                    .frame(width: 32, height: 32).background(Theme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(name).font(.subheadline.bold()).foregroundStyle(Theme.text)
                                        Text(m.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Theme.text2)
                                    }
                                    Text(m.text).foregroundStyle(Theme.text)
                                }
                            }
                            .id(m.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages?.messages.count) {
                    if let last = messages?.messages.last { scroller.scrollTo(last.id, anchor: .bottom) }
                }
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 12).accessibilityIdentifier("chatNote")
            }
            HStack(spacing: 8) {
                TextField(String(localized: "chat.message \(title)"), text: $text, axis: .vertical)
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("message")
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.background)
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("thread.send"))
            }
            .padding(12)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A room's call (channels and private rooms; an end-to-end room has none).
            if room.encrypted != true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { calling = true } label: { Image(systemName: "video") }
                        .accessibilityLabel(Text("call.start"))
                        .accessibilityIdentifier("call")
                }
            }
        }
        .fullScreenCover(isPresented: $calling) { CallView(room: room.id, title: title) }
        .task { await load() }
    }

    private func load() async {
        guard let client = model.client else { return }
        let id = room.id
        try? await quickly({ try await client.messages(in: id) }) { messages = $0 }
    }

    private func send() async {
        guard let client = model.client else { return }
        let said = text
        text = ""
        do {
            try await client.say(said, in: room.id)
            note = nil
        } catch let e as APIError where e.code == "queued" {
            note = String(localized: "offline.queued")
        } catch {
            // Not sent: the words come back.
            text = said
            note = model.say(error)
        }
        await load()
    }
}

/// An end-to-end room: its messages opened on the phone, one that cannot
/// be opened said so (never its ciphertext), and what is written sealed
/// here. Without the library or its keys, the room says to use a computer.
struct SealedChannelView: View {
    @EnvironmentObject var model: AppModel
    let room: Room
    let title: String
    @State private var messages: Messages?
    @State private var texts: [String: String?] = [:]
    @State private var unavailable = false
    @State private var text = ""
    @State private var note: String?

    var body: some View {
        if unavailable {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Theme.text2).accessibilityHidden(true)
                Text("chat.locked").multilineTextAlignment(.center).foregroundStyle(Theme.text2)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle(title)
            .accessibilityIdentifier("locked")
        } else {
            sealed
        }
    }

    private var sealed: some View {
        VStack(spacing: 0) {
            Label("chat.sealed", systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.text2).padding(.top, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages?.messages.filter { $0.deleted != true && $0.thread == nil } ?? []) { m in
                        let name = messages?.people[m.sender]?.name ?? m.sender
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(name).font(.subheadline.bold()).foregroundStyle(Theme.text)
                                Text(m.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Theme.text2)
                            }
                            if let shown = texts[m.id] ?? nil {
                                Text(shown).foregroundStyle(Theme.text).accessibilityIdentifier("opened")
                            } else {
                                Text("chat.cannotOpen").font(.subheadline).foregroundStyle(Theme.text2).accessibilityIdentifier("cannotOpen")
                            }
                        }
                        .id(m.id)
                    }
                }
                .padding(16)
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 12).accessibilityIdentifier("chatNote")
            }
            HStack(spacing: 8) {
                TextField(String(localized: "chat.message \(title)"), text: $text, axis: .vertical)
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("message")
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.background)
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("thread.send"))
                .accessibilityIdentifier("sendChat")
            }
            .padding(12)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("sealedRoom")
        .task { await load() }
    }

    private func me() async -> String? {
        if let me = model.chatMe { return me }
        let me = try? await model.client?.rooms().me
        model.chatMe = me
        return me
    }

    private func load() async {
        guard let client = model.client, let e2e = model.endToEnd() else { return }
        guard let me = await me() else { unavailable = true; return }
        do {
            let got = try await client.messages(in: room.id)
            texts = try await e2e.read(me: me, room: room.id, messages: got.messages)
            messages = got
        } catch where EndToEnd.unavailable(error) {
            unavailable = true
        } catch {
            note = model.say(error)
        }
    }

    private func send() async {
        guard let e2e = model.endToEnd(), let me = await me() else { return }
        let said = text
        text = ""
        note = nil
        do {
            _ = try await e2e.send(me: me, room: room.id, text: said)
        } catch {
            // Not sent (never in the clear): the words come back.
            text = said
            note = model.say(error)
        }
        await load()
    }
}
