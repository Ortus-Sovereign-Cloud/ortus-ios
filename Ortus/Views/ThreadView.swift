import OrtusKit
import SwiftUI

/// MobileThread: the messages of a thread, an invitation to answer (Yes,
/// Maybe, No), and a quick reply.
struct ThreadView: View {
    @EnvironmentObject var model: AppModel
    let threadID: String
    @State private var emails: [Email] = []
    @State private var reply = ""
    @State private var note: String?
    @State private var sending = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let first = emails.first {
                        Text(first.subject).font(.title2.bold()).foregroundStyle(Theme.text)
                        Text("thread.count \(emails.count)").font(.subheadline).foregroundStyle(Theme.text2)
                    }
                    ForEach(emails) { e in Message(email: e, answer: { await answer(e, $0) }) }
                    if let note { Text(note).font(.callout).foregroundStyle(Theme.text2).accessibilityIdentifier("note") }
                }
                .padding(16)
            }
            HStack(spacing: 8) {
                TextField(String(localized: "thread.reply \(emails.last?.sender ?? "")"), text: $reply, axis: .vertical)
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("reply")
                    .focused($typing)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.background)
                }
                .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                .accessibilityLabel(Text("thread.send"))
            }
            .padding(12)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let client = model.client else { return }
        let id = threadID
        try? await quickly({ try await client.thread(id) }) { emails = $0 }
        let unread = emails.filter(\.unread).map(\.id)
        if !unread.isEmpty { try? await client.markRead(unread) }
    }

    private func answer(_ email: Email, _ answer: String) async {
        guard let client = model.client else { return }
        do {
            try await client.rsvp(email, answer: answer)
            await load()
        } catch {
            note = model.say(error)
        }
    }

    private func send() async {
        guard let client = model.client, let last = emails.last else { return }
        sending = true
        defer { sending = false }
        do {
            try await client.reply(to: last, text: reply)
            reply = ""
            // Sent: the keyboard goes, the tab bar is back.
            typing = false
            note = String(localized: "thread.sent")
            await load()
        } catch let e as APIError where e.code == "queued" {
            reply = ""
            typing = false
            note = String(localized: "offline.queued")
        } catch {
            note = model.say(error)
        }
    }
}

private struct Message: View {
    let email: Email
    let answer: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(initials(email.sender)).font(.footnote.bold()).foregroundStyle(Theme.background)
                    .frame(width: 36, height: 36).background(Theme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.sender).font(.headline).foregroundStyle(Theme.text)
                    if email.ortusVerified == true {
                        Text("thread.verified").font(.caption).foregroundStyle(Theme.teal)
                    }
                }
                Spacer()
                Text(when(email.date)).font(.footnote).foregroundStyle(Theme.text2)
            }
            Text(email.ortusText ?? email.preview ?? "").foregroundStyle(Theme.text)
            if let invite = email.ortusInvite, invite.method == "REQUEST", !invite.cancelled {
                Invitation(invite: invite, answer: answer)
            }
            // How a message one sent is getting to each recipient outside.
            if let delivery = email.ortusDelivery, !delivery.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(delivery.enumerated()), id: \.offset) { _, d in
                        let to = d.recipient ?? ""
                        switch d.state {
                        case "sent": Label(String(localized: "delivery.done \(to)"), systemImage: "checkmark").foregroundStyle(Theme.teal)
                        case "bounced": Label(String(localized: "delivery.notDone \(to)"), systemImage: "xmark").foregroundStyle(.red)
                        case "deferred": Label(String(localized: "delivery.retrying \(to)"), systemImage: "clock").foregroundStyle(.orange)
                        default: Label(String(localized: "delivery.sendingTo \(to)"), systemImage: "paperplane").foregroundStyle(Theme.text2)
                        }
                    }
                }
                .font(.footnote)
                .accessibilityIdentifier("delivery")
            }
        }
    }
}

private struct Invitation: View {
    let invite: Invite
    let answer: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let start = invite.start.map({ Date(timeIntervalSince1970: Double($0) / 1000) }) {
                    VStack {
                        Text(start.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold()).foregroundStyle(Theme.accent)
                        Text(start.formatted(.dateTime.day())).font(.title3.bold()).foregroundStyle(Theme.text)
                    }
                    .frame(width: 48, height: 48).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading) {
                    Text(invite.summary).font(.headline).foregroundStyle(Theme.text)
                    if let s = invite.start, let e = invite.end {
                        Text("\(Date(timeIntervalSince1970: Double(s) / 1000).formatted(date: .omitted, time: .shortened))–\(Date(timeIntervalSince1970: Double(e) / 1000).formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(Theme.text2)
                    }
                }
            }
            HStack(spacing: 8) {
                choice("rsvp.yes", "accepted", "ACCEPTED")
                choice("rsvp.maybe", "tentative", "TENTATIVE")
                choice("rsvp.no", "declined", "DECLINED")
            }
        }
        .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }

    private func choice(_ label: LocalizedStringKey, _ value: String, _ state: String) -> some View {
        let chosen = invite.answer == state
        return Button { Task { await answer(value) } } label: {
            Text(label).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(chosen ? Theme.background : Theme.text)
                .background(chosen ? Theme.accent : Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
