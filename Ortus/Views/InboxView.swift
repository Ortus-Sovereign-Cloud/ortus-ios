import OrtusKit
import SwiftUI

/// MobileInbox: the categories with their unread counts, threads newest
/// first (who, subject, when; unread in bold), opening a thread.
struct InboxView: View {
    @EnvironmentObject var model: AppModel
    @State private var category: JMAP.Category = .important
    @State private var emails: [Email] = []
    @State private var unread: [JMAP.Category: Int] = [:]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
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
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                ForEach(emails) { e in
                    NavigationLink(value: e.threadId) { Row(email: e) }
                        .listRowBackground(Theme.background)
                }
                if emails.isEmpty && error == nil {
                    Text("inbox.empty").foregroundStyle(Theme.text2).listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("inbox.title")
            .navigationDestination(for: String.self) { ThreadView(threadID: $0) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func chip(_ c: JMAP.Category) -> String {
        let name = String(localized: String.LocalizationValue("inbox.\(c.rawValue)"))
        let n = unread[c] ?? 0
        return n > 0 ? "\(name) \(n.formatted())" : name
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            let got = try await client.inbox(category)
            emails = got.emails
            unread = got.unread
            error = nil
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(initials(email.sender)).font(.footnote.bold()).foregroundStyle(Theme.background)
                .frame(width: 40, height: 40).background(Theme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email.sender).font(.body.weight(email.unread ? .bold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
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
