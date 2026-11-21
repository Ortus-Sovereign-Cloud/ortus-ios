import SwiftUI
import VisionKit
import OrtusKit

/// First start: the installation's address and the code from the welcome
/// letter (or the invitation link itself).
struct JoinView: View {
    @EnvironmentObject var model: AppModel
    @State private var server = ProcessInfo.processInfo.environment["ORTUS_SERVER"] ?? ""
    @State private var withPhone = false
    @State private var code = ProcessInfo.processInfo.environment["ORTUS_CODE"] ?? ""

    @State private var withPassword = false
    @State private var scanning = false
    /// The code field takes the keyboard when it appears (it replaces the
    /// password field, which had it).
    @FocusState private var codeFocused: Bool

    /// AutoFill offers the code (from Passwords) in the app people use; UI
    /// tests type it, which the one-time-code field drops under XCUITest.
    /// The number pad for the code; debug builds (the UI tests, on a
    /// simulator with a hardware keyboard, which drops typing into a number
    /// pad field) the plain keyboard.
    private static var codeKeyboard: UIKeyboardType {
        #if DEBUG
        return .default
        #else
        return .numberPad
        #endif
    }

    private static var codeHint: UITextContentType? {
        #if DEBUG
        return nil
        #else
        return .oneTimeCode
        #endif
    }
    @State private var email = ""
    @State private var password = ""
    @State private var totp = ""

    private func field(_ title: LocalizedStringKey, _ text: Binding<String>, id: String) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier(id)
    }

    private func primary(_ title: LocalizedStringKey, disabled: Bool, id: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(16)
        }
        .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(model.busy || disabled)
        .accessibilityIdentifier(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Mark()
            Text("join.title").font(.largeTitle.bold()).foregroundStyle(Theme.text)
            Text("join.lead").foregroundStyle(Theme.text2)
            TextField("join.server", text: $server)
                .textContentType(.URL).keyboardType(server.contains("@") ? .emailAddress : .URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("server")
            if !withPassword {
                TextField("join.code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("code")
                // The invitation's QR code, read by the camera (where it can).
                if DataScannerViewController.isSupported {
                    Button { scanning = true } label: {
                        Label("join.scan", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.busy)
                    .accessibilityIdentifier("scan")
                }
            } else if model.ticket == nil {
                field("join.email", $email, id: "email").keyboardType(.emailAddress).textContentType(.username)
                SecureField("join.password", text: $password)
                    .textContentType(.password)
                    .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("password")
                    .submitLabel(.go)
                    .onSubmit {
                        if !server.isEmpty, email.contains("@"), !password.isEmpty {
                            Task { await model.signInWithPassword(server: server, email: email, password: password) }
                        }
                    }
            } else {
                field("join.totp", $totp, id: "totp").keyboardType(Self.codeKeyboard).textContentType(Self.codeHint)
                    .focused($codeFocused)
                    .submitLabel(.go)
                    .onSubmit { if totp.filter(\.isNumber).count >= 6 { Task { await model.signInWithCode(totp) } } }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("error")
            }
            Spacer()
            if !withPassword {
                primary("join.continue", disabled: server.isEmpty || code.isEmpty, id: "Continue") { await model.join(server: server, code: code) }
            } else if model.ticket == nil {
                primary("join.signIn", disabled: server.isEmpty || !email.contains("@") || password.isEmpty, id: "signIn") {
                    await model.signInWithPassword(server: server, email: email, password: password)
                }
            } else {
                primary("join.signIn", disabled: totp.filter(\.isNumber).count < 6, id: "signInCode") { await model.signInWithCode(totp) }
            }
            // The phone is already their key: back in without a new invitation.
            if withPhone {
                Button {
                    Task { await model.signInAgain(server: server) }
                } label: {
                    Text("join.withPhone").font(.headline).frame(maxWidth: .infinity).padding(16)
                }
                .buttonStyle(.bordered).clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(model.busy || server.isEmpty)
                .accessibilityIdentifier("withPhone")
            }
            Button(withPassword ? "join.withCode" : "join.withPassword") {
                withPassword.toggle()
                model.ticket = nil
                model.error = nil
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("togglePassword")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .onAppear {
            if server.isEmpty, let managed = model.managedServer { server = managed }
            if server.isEmpty, let last = model.lastServer { server = last.absoluteString }
            withPhone = model.hasKey(for: server)
        }
        .onChange(of: server) { withPhone = model.hasKey(for: server) }
        .onChange(of: model.ticket) {
            if model.ticket != nil { codeFocused = true }
        }
        // An invitation handed to the app fills in what it joins with.
        .onChange(of: model.handed) {
            if let handed = model.handed {
                server = handed.server
                code = handed.code
                withPassword = false
            }
        }
        .sheet(isPresented: $scanning) {
            CodeScanner { text in
                scanning = false
                model.open(text)
            }
            .ignoresSafeArea()
        }
    }
}

/// The camera, reading an invitation's QR code.
struct CodeScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        /// The first QR code that is an Ortus invitation.
        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in added {
                guard !done, case .barcode(let code) = item, let text = code.payloadStringValue,
                      InvitationLink.parse(text) != nil else { continue }
                done = true
                scanner.stopScanning()
                found(text)
            }
        }
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
        .accessibilityElement()
        .accessibilityLabel("Ortus")
        .accessibilityIdentifier("mark")
        .padding(.bottom, 16)
    }
}
