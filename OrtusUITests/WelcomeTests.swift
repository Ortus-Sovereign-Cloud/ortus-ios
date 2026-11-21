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

        // S1.9: she signs the flood plan on her phone, with its key.
        app.tabBars.buttons["More"].tap()
        app.buttons["For you"].tap()
        XCTAssertTrue(app.staticTexts["Flood response plan 2026"].waitForExistence(timeout: 20))
        attach(app, "s1.9-approvals")
        app.buttons["decide"].tap()
        XCTAssertTrue(app.staticTexts["Signed."].waitForExistence(timeout: 20), app.staticTexts["note"].exists ? app.staticTexts["note"].label : "not signed")

        // Signing out ends the session; the phone signs her in again on its own.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["withPhone"].waitForExistence(timeout: 20))
        app.buttons["withPhone"].tap()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20), app.staticTexts["error"].exists ? app.staticTexts["error"].label : "not back in")
    }

    /** S2.4: the IT administrator fixes the failed mailbox imports from the phone. */
    func testAnAdministratorFixesImports() throws {
        try need("ORTUS_SERVER", "ORTUS_ADMIN_CODE")
        let code = ProcessInfo.processInfo.environment["ORTUS_ADMIN_CODE"]!
        let app = app()
        app.launchEnvironment["ORTUS_CODE"] = code
        app.launch()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 20))
        app.buttons["makeKey"].tap()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
        app.tabBars.buttons["More"].tap()
        app.buttons["Admin"].tap()
        // The import fails on its own; pull to look again until it shows.
        let ask = app.buttons["askOwners"]
        for _ in 0..<12 where !ask.exists {
            app.swipeDown()
            _ = ask.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(ask.exists)
        attach(app, "s2.4-admin")
        ask.tap()
        XCTAssertTrue(app.staticTexts["The owners have a reconnect link in their inbox."].waitForExistence(timeout: 20))
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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
