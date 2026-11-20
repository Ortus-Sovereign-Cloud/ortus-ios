import SwiftUI

/// First start: the installation's address and the code from the welcome
/// letter (or the invitation link itself).
struct JoinView: View {
    @EnvironmentObject var model: AppModel
    @State private var server = ProcessInfo.processInfo.environment["ORTUS_SERVER"] ?? ""
    @State private var code = ProcessInfo.processInfo.environment["ORTUS_CODE"] ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Mark()
            Text("join.title").font(.largeTitle.bold()).foregroundStyle(Theme.text)
            Text("join.lead").foregroundStyle(Theme.text2)
            TextField("join.server", text: $server)
                .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("server")
            TextField("join.code", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("code")
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("error")
            }
            Spacer()
            Button {
                Task { await model.join(server: server, code: code) }
            } label: {
                Text("join.continue").font(.headline).frame(maxWidth: .infinity).padding(16)
            }
            .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(model.busy || server.isEmpty || code.isEmpty)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }
}

/// The Ortus mark.
struct Mark: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                UnevenRoundedRectangle(topLeadingRadius: 22, style: .continuous).fill(Theme.accent).frame(width: 22, height: 20)
                UnevenRoundedRectangle(topTrailingRadius: 22, style: .continuous).fill(Theme.accent).frame(width: 22, height: 20)
            }
            Capsule().fill(Theme.teal).frame(width: 47, height: 5)
        }
        .accessibilityHidden(true)
        .padding(.bottom, 16)
    }
}
