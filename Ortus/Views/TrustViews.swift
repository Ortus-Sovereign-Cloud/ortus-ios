// Trust in end-to-end rooms on the phone: recovery with the recovery key
// (set up on a computer), and verification by emoji with another device.
import OrtusE2E
import SwiftUI

/// The 64 emoji of Matrix's verification, by number (VoiceOver names them).
let sasEmoji = [
    "🐶", "🐱", "🦁", "🐎", "🦄", "🐷", "🐘", "🐰", "🐼", "🐓", "🐧", "🐢", "🐟", "🐙", "🦋", "🌷",
    "🌳", "🌵", "🍄", "🌏", "🌙", "☁️", "🔥", "🍌", "🍎", "🍓", "🌽", "🍕", "🎂", "❤️", "😀", "🤖",
    "🎩", "👓", "🔧", "🎅", "👍", "☂️", "⌛", "⏰", "🎁", "💡", "📕", "✏️", "📎", "✂️", "🔒", "🔑",
    "🔨", "☎️", "🏁", "🚂", "🚲", "✈️", "🚀", "🏆", "⚽", "🎸", "🎺", "🔔", "⚓", "🎧", "📁", "📌",
]

/// Recovery: set up on a computer; with it set up, the recovery key brings
/// this phone's history and vouches for it; recovered, it can verify the
/// person's other device.
struct RecoverySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var state: RecoveryState?
    @State private var key = ""
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                if let state {
                    if !state.set {
                        Text("chat.recoveryOnComputer")
                    } else if !state.here {
                        Text("chat.recoveryEnterLead")
                        TextField(String(localized: "chat.recoveryKey"), text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
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
            .task {
                guard let me = model.chatMe else { return }
                state = try? await model.endToEnd()?.recoveryState(me: me)
            }
        }
        .accessibilityIdentifier("recovery")
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

/// Verifications by emoji, for the whole app: looked for every few seconds
/// while the app is active and this phone's keys are open.
struct VerificationsOverlay: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var shown: VerificationView?
    @State private var dismissed: Set<String> = []

    func body(content: Content) -> some View {
        content
            .task {
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
                sheet(item.view).presentationDetents([.medium])
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

    @ViewBuilder
    private func sheet(_ v: VerificationView) -> some View {
        let me = model.chatMe ?? ""
        VStack(spacing: 16) {
            Text("chat.verifyTitle").font(.headline).accessibilityAddTraits(.isHeader)
            switch v.state {
            case "incoming":
                Text("chat.verifyIncoming")
                HStack {
                    Button("chat.verifyDecline") { close(v) }.buttonStyle(.bordered)
                    Button("chat.verifyAccept") { Task { try? await model.endToEnd()?.acceptVerification(me: me, id: v.id) } }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("verifyAccept")
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
                    Button("chat.verifyDifferent") { Task { try? await model.endToEnd()?.confirmVerification(me: me, id: v.id, same: false) } }
                        .buttonStyle(.bordered)
                    Button("chat.verifySame") { Task { try? await model.endToEnd()?.confirmVerification(me: me, id: v.id, same: true) } }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("verifySame")
                }
            case "done":
                Text("chat.verifyDone")
                Button("chat.close") { close(v) }
            case "cancelled":
                Text("chat.verifyCancelled")
                Button("chat.close") { close(v) }
            default:
                Text("chat.verifyWaiting")
                ProgressView()
            }
        }
        .padding(24)
        .accessibilityIdentifier("verification")
    }
}
