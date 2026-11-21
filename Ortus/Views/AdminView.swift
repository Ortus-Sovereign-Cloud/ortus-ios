import OrtusKit
import SwiftUI

/// MobileAdmin: what needs the administrator (mailbox imports that failed:
/// ask their owners, or retry with the password they gave), and inviting
/// someone.
struct AdminView: View {
    @EnvironmentObject var model: AppModel
    @State private var imports: [MailImport] = []
    @State private var note: String?
    @State private var passwords: [String: String] = [:]
    @State private var inviteName = ""
    @State private var inviteEmail = ""

    private var failed: [ImportAccount] { imports.flatMap(\.accounts).filter(\.failed) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: failed.isEmpty ? "checkmark" : "exclamationmark")
                        .font(.title3.bold()).foregroundStyle(failed.isEmpty ? Theme.teal : .orange)
                        .frame(width: 44, height: 44).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading) {
                        Text(failed.isEmpty ? "admin.normal" : "admin.needs").font(.headline).foregroundStyle(Theme.text)
                        Text("admin.things \(failed.count)").font(.subheadline).foregroundStyle(Theme.text2)
                    }
                }
            }
            if !failed.isEmpty {
                Section("admin.needsYou") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("admin.migration").font(.caption).foregroundStyle(Theme.text2)
                        Text("admin.failed \(failed.count)").font(.headline).foregroundStyle(Theme.text)
                        Button("admin.askOwners") { Task { await ask() } }.accessibilityIdentifier("askOwners")
                    }
                    ForEach(failed) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(a.login).foregroundStyle(Theme.text)
                            Text(a.error ?? "").font(.caption).foregroundStyle(.orange)
                            HStack {
                                SecureField("admin.newPassword", text: Binding(get: { passwords[a.id] ?? "" }, set: { passwords[a.id] = $0 }))
                                    .accessibilityIdentifier("password-\(a.login)")
                                Button("admin.retry") { Task { await retry(a) } }
                                    .disabled((passwords[a.id] ?? "").isEmpty)
                                    .accessibilityIdentifier("retry-\(a.login)")
                            }
                        }
                    }
                }
            }
            Section("admin.invite") {
                TextField("admin.name", text: $inviteName)
                TextField("share.address", text: $inviteEmail).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                Button("admin.inviteButton") { Task { await invite() } }.disabled(!inviteEmail.contains("@") || inviteName.isEmpty)
            }
            if let note { Text(note).foregroundStyle(Theme.text2).accessibilityIdentifier("note") }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("admin.title")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async { imports = (try? await model.client?.imports()) ?? [] }

    private func run(_ done: String, _ work: () async throws -> Void) async {
        do {
            try await work()
            note = String(localized: String.LocalizationValue(done))
            await load()
        } catch {
            note = model.say(error)
        }
    }

    private func ask() async { await run("admin.asked") { try await model.client?.askOwners(failed) } }
    private func retry(_ a: ImportAccount) async { await run("admin.retrying") { try await model.client?.retry(a, password: passwords[a.id] ?? "") } }
    private func invite() async {
        await run("admin.invited") { try await model.client?.invite(name: inviteName, email: inviteEmail) }
        inviteName = ""
        inviteEmail = ""
    }
}
