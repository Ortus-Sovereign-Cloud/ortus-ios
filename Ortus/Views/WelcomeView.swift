import SwiftUI

/// MobileWelcome: the code was accepted; Face ID guards the key; the phone
/// becomes the person's key.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Mark()
            Text("welcome.title \(model.me?.name.components(separatedBy: " ").first ?? "")")
                .font(.largeTitle.bold()).foregroundStyle(Theme.text)
                .accessibilityIdentifier("welcome")
            Step(state: .done, title: "welcome.code", detail: "welcome.codeDetail")
            Step(state: .done, title: "welcome.face", detail: "welcome.faceDetail")
            Step(state: .next(3), title: "welcome.key", detail: "welcome.keyDetail")
            VStack(alignment: .leading, spacing: 8) {
                Text("welcome.seeTitle").font(.subheadline.bold()).foregroundStyle(Theme.text)
                Text("welcome.seeYes").font(.subheadline).foregroundStyle(Theme.teal)
                Text("welcome.seeNo").font(.subheadline).foregroundStyle(Theme.text2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("error")
            }
            Spacer()
            Button {
                Task { await model.makeKey() }
            } label: {
                Text("welcome.makeKey").font(.headline).frame(maxWidth: .infinity).padding(16)
            }
            .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(model.busy)
            .accessibilityIdentifier("makeKey")
            Text("welcome.lost").font(.footnote).foregroundStyle(Theme.text2).frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }
}

private struct Step: View {
    enum State { case done, next(Int) }
    let state: State
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark").foregroundStyle(Theme.teal).background(Theme.teal.opacity(0.15).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8)))
                case .next(let n): Text("\(n)").bold().foregroundStyle(Theme.background).background(Theme.accent.frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8)))
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(detail).font(.subheadline).foregroundStyle(Theme.text2)
            }
        }
    }
}
