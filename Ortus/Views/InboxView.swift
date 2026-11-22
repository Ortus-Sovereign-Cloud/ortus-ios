import OrtusKit
import SwiftUI

/// MobileInbox: the categories with their unread counts, threads newest
/// first (who, subject, when; unread in bold), opening a thread.
struct InboxView: View {
    @EnvironmentObject var model: AppModel
    @State private var category: JMAP.Category = .important
    @State private var folder: JMAP.Folder = .inbox
    @State private var composing = false
    @State private var note: String?
    @State private var emails: [Email] = []
    @State private var unread: [JMAP.Category: Int] = [:]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if folder == .inbox {
                Section {
                    HStack(spacing: 8) {
                        ForEach(JMAP.Category.allCases, id: \.self) { c in
                            Button {
                                category = c
                                Task { await load() }
                            } label: {
                                Text(chip(c)).font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(c == category ? Theme.background : Theme.text)
                                    .background(c == category ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(c == category ? .isSelected : [])
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if let note {
                    Text(note).font(.callout).foregroundStyle(Theme.text2).listRowBackground(Color.clear).accessibilityIdentifier("note")
                }
                ForEach(emails) { e in
                    NavigationLink(value: e.threadId) { Row(email: e, sent: folder == .sent) }
                        .listRowBackground(Theme.background)
                }
                if emails.isEmpty && error == nil {
                    Text("inbox.empty").foregroundStyle(Theme.text2).listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(name(folder))
            .sheet(isPresented: $composing) {
                ComposeView(sent: {
                    note = String(localized: "thread.sent")
                    Task { await load() }
                })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel(Text("compose.title"))
                        .accessibilityIdentifier("compose")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(JMAP.Folder.allCases, id: \.self) { f in
                            Button {
                                folder = f
                                emails = []
                                Task { await load() }
                            } label: {
                                if f == folder { Label(name(f), systemImage: "checkmark") } else { Text(name(f)) }
                            }
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(Text("folder.choose"))
                    .accessibilityIdentifier("folders")
                }
            }
            .navigationDestination(for: String.self) { ThreadView(threadID: $0) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func chip(_ c: JMAP.Category) -> String {
        // The key built first: an interpolation inside a LocalizationValue
        // is a format argument, so "inbox.%@" would be looked up instead.
        let key = "inbox." + c.rawValue
        let name = String(localized: String.LocalizationValue(stringLiteral: key))
        let n = unread[c] ?? 0
        return n > 0 ? "\(name) \(n.formatted())" : name
    }

    private func name(_ f: JMAP.Folder) -> String {
        String(localized: String.LocalizationValue(stringLiteral: "folder." + f.rawValue))
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            if folder == .inbox {
                let category = category
                try await quickly({ try await client.inbox(category) }) { got in
                    emails = got.emails
                    unread = got.unread
                }
            } else {
                let folder = folder
                try await quickly({ try await client.folder(folder) }) { emails = $0 }
            }
            error = nil
        } catch {
            self.error = model.say(error)
        }
    }
}

/// Two letters for a sender.
func initials(_ name: String) -> String {
    let words = name.split(separator: " ").prefix(2)
    let letters = words.compactMap(\.first).map(String.init).joined()
    return (letters.isEmpty ? String(name.prefix(2)) : letters).uppercased()
}

private struct Row: View {
    let email: Email
    /// In Sent: who it went to, and how its delivery goes.
    var sent = false

    private var who: String { sent ? email.recipients : email.sender }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(initials(who)).font(.footnote.bold()).foregroundStyle(Theme.background)
                .frame(width: 40, height: 40).background(Theme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(who).font(.body.weight(email.unread && !sent ? .bold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    if sent, let state = email.deliveryState {
                        Text(state == "failed" ? "delivery.failed" : "delivery.trying")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(state == "failed" ? Color.red : Color.orange)
                    }
                    Text(when(email.date)).font(.footnote).foregroundStyle(Theme.text2)
                }
                Text(email.subject).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// "10:42" today, "Tue" this week, else "17 Nov".
func when(_ date: Date?) -> String {
    guard let date else { return "" }
    let cal = Calendar.current
    if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
    if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
    return date.formatted(.dateTime.day().month(.abbreviated))
}
