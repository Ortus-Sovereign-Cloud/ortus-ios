// Trust in end-to-end rooms on the phone: recovery with the recovery key
// (set up here or on a computer), and verification with another device, by
// QR code or by emoji.
import OrtusE2E
import OrtusKit
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// The 64 emoji of Matrix's verification, by number (VoiceOver names them).
let sasEmoji = [
    "🐶", "🐱", "🦁", "🐎", "🦄", "🐷", "🐘", "🐰", "🐼", "🐓", "🐧", "🐢", "🐟", "🐙", "🦋", "🌷",
    "🌳", "🌵", "🍄", "🌏", "🌙", "☁️", "🔥", "🍌", "🍎", "🍓", "🌽", "🍕", "🎂", "❤️", "😀", "🤖",
    "🎩", "👓", "🔧", "🎅", "👍", "☂️", "⌛", "⏰", "🎁", "💡", "📕", "✏️", "📎", "✂️", "🔒", "🔑",
    "🔨", "☎️", "🏁", "🚂", "🚲", "✈️", "🚀", "🏆", "⚽", "🎸", "🎺", "🔔", "⚓", "🎧", "📁", "📌",
]

/// The end-to-end library's refusals of an escrow key (its words, said
/// here in the person's language).
let escrowUnsigned = "The organisation's escrow key is not signed by an administrator: ask them to make it again."
let escrowNotAccepted = "The organisation's escrow key is not the one you were shown: look at it again."

/// Recovery: set up here (the key shown once, after the organisation's
/// escrow key that can recover the person's history too: its fingerprint,
/// who set it and whether the person verified them) or on a computer; with
/// it set up, the recovery key brings this phone's history and vouches for it;
/// recovered, it can verify the person's other device.
struct RecoverySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var state: RecoveryState?
    @State private var key = ""
    @State private var note: String?
    @State private var busy = false
    /// The recovery key just made here: shown this once.
    @State private var madeKey: String?
    /// The organisation's escrow key, as shown to the person: set-up seals
    /// the recovery key to this one only. Set-up is offered once it is
    /// known (none, or a signed one), never after an error.
    @State private var escrow: EscrowInfo?
    @State private var escrowKnown = false

    var body: some View {
        NavigationStack {
            Form {
                if let madeKey {
                    Text("chat.recoveryKeyLead")
                    Text(madeKey)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .privacySensitive()
                        .accessibilityIdentifier("recoveryKeyShown")
                    Button {
                        copy(madeKey)
                    } label: {
                        Label("chat.recoveryCopy", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("recoveryCopy")
                    Text("chat.recoveryKeepSafe").font(.footnote)
                    Button("chat.recoverySaved") {
                        self.madeKey = nil
                        note = nil
                        Task { await reload() }
                    }
                    .accessibilityIdentifier("recoverySaved")
                } else if let state {
                    if !state.set {
                        Text("chat.recoverySetUpLead")
                        if let escrow {
                            Text(escrowLine(escrow)).accessibilityIdentifier("recoveryEscrow")
                            if escrow.changed {
                                Text("chat.recoveryEscrowChanged").accessibilityIdentifier("recoveryEscrowChanged")
                            }
                        }
                        if escrowKnown {
                            Button("chat.recoverySetUp") { Task { await setUp() } }
                                .disabled(busy)
                                .accessibilityIdentifier("recoverySetUp")
                        }
                    } else if !state.here {
                        Text("chat.recoveryEnterLead")
                        TextField(String(localized: "chat.recoveryKey"), text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .privacySensitive()
                            .accessibilityIdentifier("recoveryKey")
                        Button("chat.recoveryEnter") { Task { await recover() } }
                            .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("recover")
                    } else {
                        Text("chat.recoveryHere")
                        Button("chat.verifyMine") {
                            Task {
                                if let me = model.chatMe { _ = try? await model.endToEnd()?.verifyOwnDevices(me: me) }
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("verifyMine")
                    }
                } else {
                    ProgressView()
                }
                if let note {
                    Text(note).accessibilityIdentifier("recoveryNote")
                }
            }
            .navigationTitle(Text("chat.recovery"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("chat.close") { dismiss() } } }
            .task { await reload() }
        }
        // The key is shown once: not swiped away by accident.
        .interactiveDismissDisabled(madeKey != nil)
        .accessibilityIdentifier("recovery")
    }

    private func reload() async {
        guard let me = model.chatMe else { return }
        state = try? await model.endToEnd()?.recoveryState(me: me)
        if state?.set == false { await loadEscrow() }
    }

    /// The escrow to show before set-up (none, or why set-up is refused).
    private func loadEscrow() async {
        escrow = nil
        escrowKnown = false
        guard let me = model.chatMe, let e2e = model.endToEnd() else { return }
        do {
            escrow = try await e2e.escrowInfo(me: me)
            escrowKnown = true
        } catch {
            note = escrowError(error)
        }
    }

    /// "Escrow key …, set by … (…)", in the web's words.
    private func escrowLine(_ e: EscrowInfo) -> String {
        let signer = EscrowSigner(signer: e.signer, status: e.signerStatus, me: model.chatMe, people: model.chatPeople)
        let you = String(localized: "chat.escrowSignerYou")
        let status: String
        switch signer.status {
        case .you: status = you
        case .verified: status = String(localized: "chat.escrowSignerVerified")
        case .unverified: status = String(localized: "chat.escrowSignerUnverified")
        }
        let name = signer.isMe ? you : signer.name
        return String(localized: "chat.recoveryEscrowInfo \(e.fingerprint) \(name) \(status)")
    }

    /// Set-up's refusals of the escrow, in the person's language.
    private func escrowError(_ error: Error) -> String {
        if case E2eError.Invalid(let detail) = error {
            if detail == escrowUnsigned { return String(localized: "chat.recoveryEscrowUnsigned") }
            if detail == escrowNotAccepted { return String(localized: "chat.recoveryEscrowNotShown") }
            return detail
        }
        return model.say(error)
    }

    /// Recovery from this phone: the key, shown once.
    private func setUp() async {
        guard let me = model.chatMe, let e2e = model.endToEnd() else { return }
        busy = true
        defer { busy = false }
        do {
            madeKey = try await e2e.setUpRecovery(me: me, acceptedEscrowKey: escrow?.key)
            note = nil
            model.trustChanged += 1
        } catch {
            let said = escrowError(error)
            // The escrow changed meanwhile: the one set-up would use now is shown.
            if case E2eError.Invalid(let detail) = error, detail == escrowNotAccepted { await loadEscrow() }
            note = said
        }
    }

    /// On this phone's clipboard only, for two minutes (it unlocks everything).
    private func copy(_ key: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: key]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
        note = String(localized: "chat.recoveryCopied")
    }

    private func recover() async {
        guard let me = model.chatMe, let e2e = model.endToEnd() else { return }
        busy = true
        defer { busy = false }
        do {
            let n = try await e2e.recover(me: me, key: key)
            note = String(localized: "chat.recoveryRestored \(Int(n))")
            state = try await e2e.recoveryState(me: me)
            model.trustChanged += 1
        } catch E2eError.Invalid(_) {
            note = String(localized: "chat.recoveryWrong")
        } catch {
            note = model.say(error)
        }
    }
}

/// The devices of a room nobody vouched for, each to verify (the
/// verification then shows over the app).
struct UnverifiedSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let devices: [DeviceRef]
    let messages: Messages?
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Text("chat.unverifiedLead").foregroundStyle(.secondary)
                ForEach(Array(devices.enumerated()), id: \.offset) { _, d in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(messages?.name(of: d.user) ?? d.user)
                            Text(String(localized: "chat.device \(d.device)")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("chat.verify") { Task { await verify(d) } }
                            .buttonStyle(.bordered)
                            .disabled(busy)
                            .accessibilityIdentifier("verify-\(d.device)")
                    }
                }
                if let note {
                    Text(note).accessibilityIdentifier("unverifiedNote")
                }
            }
            .navigationTitle(Text("chat.unverifiedTitle"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("chat.close") { dismiss() } } }
        }
        .accessibilityIdentifier("unverifiedList")
    }

    /// Asks the device; this list closes so the verification can show.
    private func verify(_ d: DeviceRef) async {
        guard let me = model.chatMe, let e2e = model.endToEnd() else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await e2e.verifyDevice(me: me, user: d.user, device: d.device)
            dismiss()
        } catch {
            note = model.say(error)
        }
    }
}

/// Verifications, for the whole app: looked for every few seconds
/// while the app is active and this phone's keys are open.
struct VerificationsOverlay: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var shown: VerificationView?
    @State private var dismissed: Set<String> = []
    /// Bumped after an answer: looked at again now, not in three seconds.
    @State private var poke = 0

    func body(content: Content) -> some View {
        content
            .task(id: poke) {
                while !Task.isCancelled {
                    if phase == .active, let me = model.chatMe, let e2e = model.endToEnd(), e2e.isOpen {
                        let list = (try? await e2e.verifications(me: me)) ?? []
                        let current = list.last { !dismissed.contains($0.id) && $0.state != "cancelled" } ?? list.last { $0.id == shown?.id }
                        if current?.state == "done", shown?.state != "done" { model.trustChanged += 1 }
                        shown = current.flatMap { dismissed.contains($0.id) ? nil : $0 }
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .sheet(item: Binding(get: { shown.map(Shown.init) }, set: { if $0 == nil, let v = shown { close(v) } })) { item in
                VerificationSheet(view: item.view, close: { close(item.view) }, answered: { poke += 1 })
                    .presentationDetents([.medium, .large])
            }
    }

    private struct Shown: Identifiable {
        let view: VerificationView
        var id: String { view.id }
    }

    private func close(_ v: VerificationView) {
        if v.state != "done" && v.state != "cancelled", let me = model.chatMe {
            Task { try? await model.endToEnd()?.cancelVerification(me: me, id: v.id) }
        }
        dismissed.insert(v.id)
        shown = nil
    }
}

/// One verification: choosing how (scan their code, show this phone's, or
/// emoji), then the code or the emoji, then the outcome.
private struct VerificationSheet: View {
    @EnvironmentObject var model: AppModel
    let view: VerificationView
    let close: () -> Void
    let answered: () -> Void
    /// This phone's code, once the library made it.
    @State private var code: QRGrid?
    @State private var scanning = false
    @State private var note: String?
    @State private var busy = false

    private var me: String { model.chatMe ?? "" }

    var body: some View {
        let v = view
        let me = self.me
        // "Show my code" draws the code at once, before the state says so.
        let state = v.state == "ready" && code != nil ? "qr" : v.state
        ScrollView {
            VStack(spacing: 16) {
                Text("chat.verifyTitle").font(.headline).accessibilityAddTraits(.isHeader)
                // Who asks, on every step: the person (or oneself) and the device.
                VerificationWho(party: VerificationParty(user: v.user, device: v.device, me: model.chatMe, people: model.chatPeople))
                switch state {
                case "incoming":
                    Text("chat.verifyIncoming")
                    HStack {
                        Button("chat.verifyDecline") { close() }.buttonStyle(.bordered)
                        Button("chat.verifyAccept") { act { try await $0.acceptVerification(me: me, id: v.id) } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("verifyAccept")
                    }
                case "ready":
                    Text("chat.verifyChoose")
                    if v.canScan && DataScannerViewController.isSupported {
                        Button { scanning = true } label: {
                            Label("chat.verifyScan", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("verifyScan")
                    }
                    if v.canShow {
                        Button { Task { await show() } } label: {
                            Label("chat.verifyShow", systemImage: "qrcode").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("verifyShow")
                    }
                    Button { emoji(v.id) } label: {
                        Label("chat.verifyByEmoji", systemImage: "face.smiling").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("verifyByEmoji")
                case "qr":
                    Text("chat.verifyShowLead")
                    if let code {
                        QRCodeImage(grid: code)
                    } else {
                        ProgressView().task { await show() }
                    }
                    Button("chat.verifyEmojiInstead") { emoji(v.id) }
                        .accessibilityIdentifier("verifyEmojiInstead")
                case "scanned":
                    Text("chat.verifyScannedAsk")
                    HStack {
                        Button("chat.verifyNo") { act { try await $0.confirmScanned(me: me, id: v.id, yes: false) } }
                            .buttonStyle(.bordered)
                        Button("chat.verifyYes") { act { try await $0.confirmScanned(me: me, id: v.id, yes: true) } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("verifyScannedYes")
                    }
                case "emoji":
                    Text("chat.verifyCompare")
                    HStack(spacing: 8) {
                        ForEach(Array(v.emoji.enumerated()), id: \.offset) { _, n in
                            Text(Int(n) < sasEmoji.count ? sasEmoji[Int(n)] : "?").font(.system(size: 34))
                        }
                    }
                    .accessibilityIdentifier("verifyEmoji")
                    HStack {
                        Button("chat.verifyDifferent") { act { try await $0.confirmVerification(me: me, id: v.id, same: false) } }
                            .buttonStyle(.bordered)
                        Button("chat.verifySame") { act { try await $0.confirmVerification(me: me, id: v.id, same: true) } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("verifySame")
                    }
                case "done":
                    Text("chat.verifyDone")
                    Button("chat.close") { close() }
                case "cancelled":
                    Text("chat.verifyCancelled")
                    Button("chat.close") { close() }
                default:
                    Text("chat.verifyWaiting")
                    ProgressView()
                }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("verifyNote")
                }
            }
            .padding(24)
            .disabled(busy)
        }
        .accessibilityIdentifier("verification")
        .sheet(isPresented: $scanning) {
            VerificationCodeScanner { scanned in
                scanning = false
                Task { await scan(scanned) }
            }
            .ignoresSafeArea()
        }
    }

    /// One answer to the library; its failure said here.
    private func act(_ work: @escaping (EndToEnd) async throws -> Void) {
        guard let e2e = model.endToEnd() else { return }
        Task {
            busy = true
            defer { busy = false }
            do {
                try await work(e2e)
                note = nil
                answered()
            } catch {
                note = model.say(error)
            }
        }
    }

    /// Emoji instead of a code: this phone's code is no longer shown.
    private func emoji(_ id: String) {
        let me = self.me
        act { e2e in
            try await e2e.startEmoji(me: me, id: id)
            code = nil
        }
    }

    private func show() async {
        guard code == nil, !busy, let e2e = model.endToEnd() else { return }
        busy = true
        defer { busy = false }
        do {
            let image = try await e2e.showQr(me: me, id: view.id)
            guard let grid = QRGrid(width: Int(image.width), modules: image.modules) else {
                note = String(localized: "error.generic")
                return
            }
            code = grid
            note = nil
            answered()
        } catch {
            note = model.say(error)
        }
    }

    private func scan(_ scanned: Data) async {
        guard let e2e = model.endToEnd() else { return }
        busy = true
        defer { busy = false }
        do {
            try await e2e.scanQr(me: me, id: view.id, scanned: scanned)
            note = nil
            answered()
        } catch E2eError.Invalid(_) {
            note = String(localized: "chat.verifyNotACode")
        } catch {
            note = model.say(error)
        }
    }
}

/// Who a verification is with: another person by name (when known) and
/// id, or "this is you"; and the device.
private struct VerificationWho: View {
    let party: VerificationParty

    var body: some View {
        VStack(spacing: 2) {
            if party.isMe {
                Text(party.device.map { String(localized: "chat.verifyYouDevice \($0)") } ?? String(localized: "chat.verifyYou"))
            } else {
                Text(String(localized: "chat.verifyWith \(party.name ?? party.user)"))
                if party.name != nil {
                    Text(party.user).font(.caption).foregroundStyle(.secondary)
                }
                if let device = party.device {
                    Text(String(localized: "chat.device \(device)")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("verifyWho")
    }
}

/// A QR code, dark on white in both appearances, with its quiet zone.
struct QRCodeImage: View {
    let grid: QRGrid

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let module = side / CGFloat(grid.width)
            context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)), with: .color(.white))
            var dark = Path()
            for row in 0..<grid.width {
                for column in 0..<grid.width where grid.dark(row, column) {
                    dark.addRect(CGRect(x: CGFloat(column) * module, y: CGFloat(row) * module, width: module, height: module))
                }
            }
            context.fill(dark, with: .color(.black))
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 280)
        .accessibilityElement()
        .accessibilityLabel(Text("chat.verifyQrLabel"))
        .accessibilityIdentifier("verifyQr")
    }
}
