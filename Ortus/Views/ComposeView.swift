import OrtusKit
import SwiftUI

/// MobileCompose: a new message. To with suggestions as one types, From
/// when one has more than one address, Subject and text. Someone with no
/// address here is told so and cannot send.
struct ComposeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Said by the inbox after a send ("Sent.").
    let sent: () -> Void

    @State private var identities: [Identity] = []
    @State private var loaded = false
    @State private var from: String = ""
    @State private var to: [String] = []
    @State private var typed = ""
    @State private var suggestions: [Suggestion] = []
    @State private var subject = ""
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                if loaded && identities.isEmpty {
                    Section { Text("compose.noAddress").foregroundStyle(.red).accessibilityIdentifier("noAddress") }
                }
                if identities.count > 1 {
                    Picker("compose.from", selection: $from) {
                        ForEach(identities) { i in Text(i.email).tag(i.id) }
                    }
                    .accessibilityIdentifier("from")
                }
                Section {
                    ForEach(to, id: \.self) { address in
                        HStack {
                            Text(address).foregroundStyle(Theme.text)
                            Spacer()
                            Button { to.removeAll { $0 == address } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.text2)
                                .accessibilityLabel(Text("compose.removeRecipient \(address)"))
                        }
                    }
                    TextField("compose.to", text: $typed)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                        .accessibilityIdentifier("to")
                        .onSubmit { add(typed) }
                        .onChange(of: typed) { Task { await suggest() } }
                    ForEach(suggestions, id: \.self) { s in
                        Button { add(s.email) } label: {
                            VStack(alignment: .leading) {
                                Text(s.shown).foregroundStyle(Theme.text)
                                Text(s.email).font(.caption).foregroundStyle(Theme.text2)
                            }
                        }
                    }
                }
                Section {
                    TextField("compose.subject", text: $subject).accessibilityIdentifier("subject")
                    TextField("compose.message", text: $text, axis: .vertical).lineLimit(6...).accessibilityIdentifier("message")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("error") }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("compose.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("compose.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("compose.send") { Task { await send() } }
                        .disabled(!canSend)
                        .accessibilityIdentifier("send")
                }
            }
            .task { await start() }
        }
    }

    private var canSend: Bool {
        !sending && !identities.isEmpty && !(to.isEmpty && !looksLikeAddress(typed))
    }

    private func looksLikeAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let at = t.firstIndex(of: "@") else { return false }
        return at != t.startIndex && t[t.index(after: at)...].contains(".") && !t.contains(" ")
    }

    private func add(_ address: String) {
        let a = address.trimmingCharacters(in: .whitespaces).lowercased()
        guard looksLikeAddress(a) else { return }
        if !to.contains(a) { to.append(a) }
        typed = ""
        suggestions = []
    }

    private func start() async {
        guard let client = model.client else { return }
        identities = (try? await client.identities()) ?? []
        from = identities.first?.id ?? ""
        loaded = true
    }

    private func suggest() async {
        let q = typed.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let client = model.client else { suggestions = []; return }
        let found = (try? await client.suggest(q)) ?? []
        // Only for what is still typed.
        if q == typed.trimmingCharacters(in: .whitespaces) { suggestions = Array(found.filter { !to.contains($0.email.lowercased()) }.prefix(5)) }
    }

    private func send() async {
        guard let client = model.client, let identity = identities.first(where: { $0.id == from }) ?? identities.first else { return }
        if looksLikeAddress(typed) { add(typed) }
        sending = true
        defer { sending = false }
        do {
            try await client.send(from: identity, to: to, subject: subject, text: text)
            sent()
            dismiss()
        } catch let e as APIError where e.code == "queued" {
            // No connection: it waits in the outbox and goes by itself.
            sent()
            dismiss()
        } catch {
            self.error = model.say(error)
        }
    }
}
