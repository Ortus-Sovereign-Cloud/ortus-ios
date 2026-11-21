import OrtusKit
import SwiftUI

/// MobileApprovals and MobileTasks: approvals at one's turn (signing asks
/// for the phone's key: Face ID, a fresh sign-in), then tasks.
struct ForYouView: View {
    @EnvironmentObject var model: AppModel
    @State private var reviews: [Review] = []
    @State private var tasks: [WorkTask] = []
    @State private var showTasks = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        tab("foryou.approvals \(reviews.count)", !showTasks) { showTasks = false }
                        tab("foryou.tasks \(tasks.filter { !$0.done }.count)", showTasks) { showTasks = true }
                    }
                    if let note { Text(note).font(.callout).foregroundStyle(Theme.text2).accessibilityIdentifier("note") }
                    if showTasks {
                        ForEach(tasks) { t in TaskRow(task: t) { await toggle(t) } }
                    } else {
                        if reviews.isEmpty { Text("foryou.nothing").foregroundStyle(Theme.text2) }
                        ForEach(reviews) { r in Card(review: r) { await decide(r, $0) } }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("foryou.title")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func tab(_ label: LocalizedStringKey, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
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
        reviews = (try? await client.waitingReviews()) ?? []
        tasks = (try? await client.myTasks()) ?? []
    }

    private func decide(_ review: Review, _ approve: Bool) async {
        guard let client = model.client else { return }
        do {
            // Signing: the phone's key again (Face ID), so the sign-in is
            // fresh, as signing asks.
            if review.signs { try await model.signInWithKey(client: client) }
            try await client.decide(review, approve: approve, comment: approve ? "" : String(localized: "foryou.sentBackComment"))
            note = String(localized: review.signs ? "foryou.signed" : "foryou.done")
            await load()
        } catch {
            note = model.say(error)
        }
    }

    private func toggle(_ t: WorkTask) async {
        try? await model.client?.setDone(t, !t.done)
        await load()
    }
}

private struct Card: View {
    let review: Review
    let decide: (Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(review.signs ? "foryou.sign" : "foryou.approve").font(.caption.bold()).foregroundStyle(.orange)
            Text(review.name ?? "").font(.headline).foregroundStyle(Theme.text)
            if let step = review.current {
                Text("foryou.step \(step.n) \(review.steps.count)").font(.subheadline).foregroundStyle(Theme.text2)
            }
            HStack(spacing: 4) {
                ForEach(review.steps, id: \.n) { s in
                    Capsule().fill(s.state == "current" ? Theme.accent : (s.state == "waiting" ? Theme.surface2 : Theme.teal)).frame(height: 4)
                }
            }
            HStack(spacing: 8) {
                Button { Task { await decide(false) } } label: {
                    Text("foryou.sendBack").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.text)
                }
                Button { Task { await decide(true) } } label: {
                    Text(review.signs ? "foryou.signWithKey" : "foryou.approveButton").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.background)
                }
                .accessibilityIdentifier("decide")
            }
            .buttonStyle(.plain)
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }
}

private struct TaskRow: View {
    let task: WorkTask
    let toggle: () async -> Void

    var body: some View {
        Button { Task { await toggle() } } label: {
            HStack(spacing: 14) {
                Image(systemName: task.done ? "checkmark.square.fill" : "square").font(.title3).foregroundStyle(task.done ? Theme.teal : Theme.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).foregroundStyle(Theme.text).strikethrough(task.done)
                    if let p = task.projectName { Text(p).font(.caption).foregroundStyle(Theme.text2) }
                }
                Spacer()
            }
            .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(task.done ? .isSelected : [])
    }
}
