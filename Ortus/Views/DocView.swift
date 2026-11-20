import OrtusKit
import SwiftUI

/// MobileDoc: a document to read on the phone, with its comments and a
/// comment box (editing is for a larger screen).
struct DocView: View {
    @EnvironmentObject var model: AppModel
    let doc: String
    @State private var text: DocText?
    @State private var comments: [DocComment] = []
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let label = text?.label { Text(label).font(.caption.bold()).foregroundStyle(.orange) }
                    Text(text?.now ?? "").foregroundStyle(Theme.text).textSelection(.enabled)
                    if !comments.isEmpty {
                        Text("doc.comments").font(.headline).foregroundStyle(Theme.text)
                        ForEach(comments.filter { $0.resolved != true }) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                if let q = c.quote, !q.isEmpty { Text("“\(q)”").font(.caption).foregroundStyle(Theme.text2) }
                                Text(c.body).foregroundStyle(Theme.text)
                                Text(c.author ?? "").font(.caption).foregroundStyle(Theme.text2)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(16)
            }
            HStack(spacing: 8) {
                TextField("doc.comment", text: $draft, axis: .vertical)
                    .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("comment")
                Button {
                    Task {
                        if let updated = try? await model.client?.comment(doc, body: draft) { comments = updated }
                        draft = ""
                    }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 40, height: 40)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.background)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("thread.send"))
            }
            .padding(12)
        }
        .background(Theme.background)
        .navigationTitle(text?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            text = try? await model.client?.docText(doc)
            comments = (try? await model.client?.comments(doc)) ?? []
        }
    }
}
