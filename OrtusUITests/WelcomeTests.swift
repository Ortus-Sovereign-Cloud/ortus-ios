import CryptoKit
import XCTest

/// The phone steps against a real Ortus (started by CI, which passes its
/// address and an invitation code as ORTUS_SERVER and ORTUS_CODE).
final class WelcomeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The step's values from CI; in CI their absence fails (not a skip).
    private func need(_ names: String...) throws {
        let env = ProcessInfo.processInfo.environment
        guard names.allSatisfy({ !(env[$0] ?? "").isEmpty }) else {
            if env["CI"] == "true" { XCTFail("\(names) are not set"); throw XCTSkip("failed") }
            throw XCTSkip("no Ortus to talk to")
        }
    }

    private func app(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        for key in ["ORTUS_SERVER", "ORTUS_CODE"] {
            if let value = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = value }
        }
        return app
    }

    /// S3.2: she installs the app, it takes the code from her welcome
    /// letter, and the phone becomes her key (she then signs in with it).
    func testThePhoneBecomesTheKey() throws {
        try need("ORTUS_SERVER", "ORTUS_CODE")
        let app = app()
        app.launch()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["welcome"].waitForExistence(timeout: 20))
        attach(app, "s3.2-welcome")
        app.buttons["makeKey"].tap()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20), app.staticTexts["error"].exists ? app.staticTexts["error"].label : "no tab bar")
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.staticTexts["iryna@ministry.example"].waitForExistence(timeout: 10))

        // Her inbox: Anna's mail; the thread; a quick reply goes out.
        app.tabBars.buttons["Mail"].tap()
        // The inbox's tabs in words, not their keys.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Important'")).firstMatch.waitForExistence(timeout: 20), "the Important tab")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'inbox.'")).firstMatch.exists, "a tab shows its key")
        let row = app.staticTexts["Gauge report and updated shelter agreement"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        attach(app, "inbox")
        row.tap()
        XCTAssertTrue(app.staticTexts["Anna Kowalska"].waitForExistence(timeout: 10))
        let reply = app.textFields["reply"]
        reply.tap()
        reply.typeText("Thanks, will review")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts["Sent."].waitForExistence(timeout: 20), app.staticTexts["note"].exists ? app.staticTexts["note"].label : "not sent")
        attach(app, "thread")

        // Her reply is in Sent, with whom it went to.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // Back in the inbox (the screen slides back first).
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 10), "back in the inbox")
        let folders = app.buttons["folders"]
        XCTAssertTrue(folders.waitForExistence(timeout: 10))
        for _ in 0..<20 where !folders.isHittable { usleep(250_000) }
        // A menu in the iOS 26 navigation bar may not take an accessibility
        // tap ("cannot scroll to visible"): tap where it is on screen.
        func openFolders() { folders.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        openFolders()
        XCTAssertTrue(app.buttons["Sent"].waitForExistence(timeout: 10))
        app.buttons["Sent"].tap()
        XCTAssertTrue(app.navigationBars["Sent"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Gauge report'")).firstMatch.waitForExistence(timeout: 20), "the reply in Sent")
        attach(app, "sent")
        openFolders()
        XCTAssertTrue(app.buttons["Inbox"].waitForExistence(timeout: 10))
        app.buttons["Inbox"].tap()

        // S1.9: she signs the flood plan on her phone, with its key.
        app.tabBars.buttons["More"].tap()
        tap(app, "foryou")
        XCTAssertTrue(app.staticTexts["Flood response plan 2026"].waitForExistence(timeout: 20))
        attach(app, "s1.9-approvals")
        app.buttons["decide"].tap()
        XCTAssertTrue(app.staticTexts["Signed."].waitForExistence(timeout: 20), app.staticTexts["note"].exists ? app.staticTexts["note"].label : "not signed")

        // Signing out ends the session; the phone signs her in again on its own.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app, "signOut")
        XCTAssertTrue(app.buttons["withPhone"].waitForExistence(timeout: 20))
        app.buttons["withPhone"].tap()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20), app.staticTexts["error"].exists ? app.staticTexts["error"].label : "not back in")
    }

    /// An invitation page on the phone hands the app its link
    /// (ortus://join): the app joins with it, and the phone becomes the key.
    func testAnInvitationLinkOpensTheApp() throws {
        try need("ORTUS_SERVER", "ORTUS_LINK_CODE")
        let env = ProcessInfo.processInfo.environment
        let app = app()
        app.launchEnvironment["ORTUS_SERVER"] = ""
        app.launchEnvironment["ORTUS_CODE"] = ""
        app.launch()
        XCTAssertTrue(app.textFields["code"].waitForExistence(timeout: 20))
        var link = URLComponents()
        link.scheme = "ortus"
        link.host = "join"
        link.queryItems = [URLQueryItem(name: "server", value: env["ORTUS_SERVER"]), URLQueryItem(name: "code", value: env["ORTUS_LINK_CODE"])]
        // As a tapped link: through the system, which hands it to the app.
        XCUIDevice.shared.system.open(link.url!)
        // iOS may ask before handing an app a link of its own scheme.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 5) { springboard.buttons["Open"].tap() }
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 30),
                      app.staticTexts["error"].exists ? app.staticTexts["error"].label : "not joined; screen:\n\(app.debugDescription)\nsystem:\n\(springboard.debugDescription)")
    }

    /// "Sign in on your phone" from the web: the code from the owner's web
    /// session, opened as the QR code or button hands it to the app, signs
    /// the app in; the phone then becomes the owner's key.
    func testSignInOnThePhoneFromTheWeb() throws {
        try need("ORTUS_SERVER", "ORTUS_OWNER_SESSION")
        let env = ProcessInfo.processInfo.environment
        var request = URLRequest(url: URL(string: env["ORTUS_SERVER"]! + "/api/v1/me/phone-link")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ortus", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Bearer \(env["ORTUS_OWNER_SESSION"]!)", forHTTPHeaderField: "Authorization")
        let done = DispatchSemaphore(value: 0)
        var body = Data()
        URLSession.shared.dataTask(with: request) { data, _, _ in body = data ?? Data(); done.signal() }.resume()
        done.wait()
        struct Made: Decodable { let link: String }
        let link = try JSONDecoder().decode(Made.self, from: body).link
        let code = String(link.split(separator: "p=").last ?? "")

        let app = app()
        app.launchEnvironment["ORTUS_SERVER"] = ""
        app.launchEnvironment["ORTUS_CODE"] = ""
        app.launch()
        XCTAssertTrue(app.textFields["code"].waitForExistence(timeout: 20))
        var open = URLComponents()
        open.scheme = "ortus"
        open.host = "signin"
        open.queryItems = [URLQueryItem(name: "server", value: env["ORTUS_SERVER"]), URLQueryItem(name: "code", value: code)]
        XCUIDevice.shared.system.open(open.url!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 5) { springboard.buttons["Open"].tap() }
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 30),
                      app.staticTexts["error"].exists ? app.staticTexts["error"].label : "not signed in; screen:\n\(app.debugDescription)")
        attach(app, "phone-link")
    }

    /// The owner signs in with a password and the authenticator's code.
    func testAPasswordAndACode() throws {
        try need("ORTUS_SERVER", "ORTUS_OWNER_TOTP")
        let app = app()
        app.launchEnvironment["ORTUS_CODE"] = ""
        app.launch()
        app.buttons["togglePassword"].tap()
        app.textFields["email"].tap()
        app.textFields["email"].typeText("taras@ministry.example")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("flood-plan-2026-ministry")
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.textFields["totp"].waitForExistence(timeout: 20), app.staticTexts["error"].exists ? app.staticTexts["error"].label : "no code step")
        let field = app.textFields["totp"]
        field.tap()
        // The code first; Return only once the field holds all of it (typed
        // together, Return could come before the last digit reached the app,
        // which then ignores it). The keyboard covers the button on a short
        // screen, so the button is the fallback.
        let code = Self.totp(ProcessInfo.processInfo.environment["ORTUS_OWNER_TOTP"]!)
        // The simulator can drop keys typed before its keyboard is up: wait
        // for it, and type again (after clearing) until the field holds the code.
        _ = app.keyboards.element.waitForExistence(timeout: 10)
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        var held = ""
        for _ in 0..<3 {
            // Typing goes nowhere until the field has the focus.
            if !((field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) {
                field.tap()
                _ = XCTWaiter().wait(for: [expectation(for: focused, evaluatedWith: field)], timeout: 5)
            }
            field.typeText(code)
            let value = field.value as? String ?? ""
            held = value == field.placeholderValue ? "" : value
            if held == code { break }
            if !held.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: held.count)) }
        }
        XCTAssertEqual(code, held, "the code is in the field; screen:\n\(app.debugDescription)")
        field.typeText("\n")
        if !app.buttons["makeKey"].waitForExistence(timeout: 5), app.buttons["signInCode"].isHittable {
            app.buttons["signInCode"].tap()
        }
        // Not yet her key: the phone offers to become it.
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 20), app.staticTexts["error"].exists ? app.staticTexts["error"].label : "not signed in")
    }

    private static func totp(_ secret: String) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, value = 0
        var key = Data()
        for c in secret.uppercased() where c != "=" {
            value = (value << 5) | (alphabet.firstIndex(of: c) ?? 0)
            bits += 5
            if bits >= 8 { key.append(UInt8((value >> (bits - 8)) & 0xff)); bits -= 8 }
        }
        var counter = UInt64(Date().timeIntervalSince1970 / 30).bigEndian
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: Data(bytes: &counter, count: 8), using: SymmetricKey(data: key)))
        let o = Int(mac[19] & 15)
        let n = (UInt32(mac[o] & 0x7f) << 24) | (UInt32(mac[o + 1]) << 16) | (UInt32(mac[o + 2]) << 8) | UInt32(mac[o + 3])
        return String(format: "%06d", n % 1_000_000)
    }

    /** S2.4: the IT administrator fixes the failed mailbox imports from the phone. */
    func testAnAdministratorFixesImports() throws {
        try need("ORTUS_SERVER", "ORTUS_ADMIN_CODE", "ORTUS_IMPORT_PASSWORDS", "ORTUS_OWNER_SESSION")
        let code = ProcessInfo.processInfo.environment["ORTUS_ADMIN_CODE"]!
        let app = app()
        app.launchEnvironment["ORTUS_CODE"] = code
        app.launch()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 20))
        app.buttons["makeKey"].tap()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
        app.tabBars.buttons["More"].tap()
        tap(app, "admin")
        // The import fails on its own; pull to look again until it shows.
        let ask = app.buttons["askOwners"]
        let both = app.staticTexts["2 mailboxes failed"]
        for _ in 0..<12 where !both.exists {
            app.swipeDown()
            _ = both.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(both.exists, "two failures")
        attach(app, "s2.4-admin")
        ask.tap()
        XCTAssertTrue(app.staticTexts["The owners have a reconnect link in their inbox."].waitForExistence(timeout: 20))
        // He puts in the right passwords and retries both.
        let right = Dictionary(uniqueKeysWithValues: ProcessInfo.processInfo.environment["ORTUS_IMPORT_PASSWORDS"]!.split(separator: ",").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts[1])
        })
        for login in right.keys.sorted() {
            let field = app.secureTextFields["password-\(login)"]
            XCTAssertTrue(field.waitForExistence(timeout: 10), login)
            field.tap()
            field.typeText(right[login]!)
            tap(app, "retry-\(login)")
            XCTAssertTrue(app.staticTexts["Trying again."].waitForExistence(timeout: 20), login)
        }
        // Both copy: nothing fails again (a wrong password fails in seconds).
        let normal = app.staticTexts["All systems normal"]
        for _ in 0..<12 where !normal.exists {
            app.swipeDown()
            _ = normal.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(normal.exists, "the imports still fail")
        // And the mail came: both accounts copied, each with its old mail
        // (asked of the server, as the owner).
        var states = ""
        for _ in 0..<90 {
            states = try Self.importStates()
            if states == "olha.old@ministry.example:done:1,petro.old@ministry.example:done:1" { break }
            sleep(1)
        }
        XCTAssertEqual("olha.old@ministry.example:done:1,petro.old@ministry.example:done:1", states)
    }

    /// Each import account as login:state:copied, from the server.
    private static func importStates() throws -> String {
        let env = ProcessInfo.processInfo.environment
        var request = URLRequest(url: URL(string: env["ORTUS_SERVER"]! + "/api/v1/mail/admin/imports")!)
        request.setValue("Bearer \(env["ORTUS_OWNER_SESSION"]!)", forHTTPHeaderField: "Authorization")
        let done = DispatchSemaphore(value: 0)
        var body = Data()
        URLSession.shared.dataTask(with: request) { data, _, _ in body = data ?? Data(); done.signal() }.resume()
        done.wait()
        struct Imports: Decodable { struct Import: Decodable { let accounts: [Account] }; struct Account: Decodable { let login: String; let state: String; let copied: Int? }; let imports: [Import] }
        let imports = try JSONDecoder().decode(Imports.self, from: body)
        return imports.imports.flatMap(\.accounts).map { "\($0.login):\($0.state):\(min($0.copied ?? 0, 1))" }.sorted().joined(separator: ",")
    }

    /// The first screen in every language; Arabic right to left.
    func testJoinScreenInSixLanguages() {
        let titles = ["en": "Join your organisation", "pl": "Dołącz do organizacji", "uk": "Приєднайтеся до організації", "de": "Ihrer Organisation beitreten", "fr": "Rejoindre votre organisation", "ar": "انضم إلى مؤسستك"]
        for (language, title) in titles {
            let app = app(language)
            app.launchEnvironment["ORTUS_SERVER"] = ""
            app.launchEnvironment["ORTUS_CODE"] = ""
            app.launch()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), language)
            // The mark sits at the start: the left in five languages, the
            // right in Arabic.
            let mark = app.otherElements["mark"].frame
            if language == "ar" {
                XCTAssertGreaterThan(mark.midX, app.frame.midX, "right to left")
                attach(app, "join-ar")
            } else {
                XCTAssertLessThan(mark.midX, app.frame.midX, language)
            }
            app.terminate()
        }
    }

    /// Taps the element with this identifier, whatever kind it is, scrolling
    /// the list to it when it is below the screen.
    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any)[id].firstMatch
        for _ in 0..<4 where !element.exists || !element.isHittable {
            if element.waitForExistence(timeout: 5), element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "\(id) is not on screen:\n\(app.debugDescription)")
        element.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
