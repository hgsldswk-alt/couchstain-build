import XCTest

private enum StoreLanguage: String {
    case en, hans = "zh-Hans", hant = "zh-Hant"

    var locale: String {
        switch self {
        case .en: return "en_US"
        case .hans: return "zh_CN"
        case .hant: return "zh_TW"
        }
    }
}

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var session: String!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        session = UUID().uuidString
    }

    func testHomeIsReadyAndTwoTapsCreateACard() {
        launch()
        XCTAssertFalse(app.buttons["stain.COF"].isEnabled)
        select("W", "COF")
        XCTAssertEqual(app.staticTexts["card.title"].label, "Fresh coffee or tea spill")
        XCTAssertTrue(app.staticTexts["card.first"].exists)
        XCTAssertTrue(app.staticTexts["card.recheckDry"].exists)
        XCTAssertTrue(app.staticTexts["card.stop"].exists)
    }

    func testTwoTapCorrectionsForBothChoices() {
        launch()
        select("W", "COF")
        tap("card.change", down: false)
        tap("care.X")
        XCTAssertEqual(app.staticTexts["card.title"].label, "Keep liquids off this fabric")
        XCTAssertFalse(app.buttons["card.markChecked"].exists)
        tap("card.change", down: false)
        tap("stain.PET")
        XCTAssertEqual(app.staticTexts["card.title"].label, "Stop and get professional help")
        XCTAssertFalse(app.buttons["card.markChecked"].exists)
    }

    func testDryCheckMilestoneAndResumeAfterRelaunch() {
        launch()
        select("W", "COF")
        markChecked()
        tap("card.home", down: false)
        tap("home.resume")
        XCTAssertTrue(visible(element("card.checked")))
        app.terminate()
        launch(reset: false)
        tap("home.resume")
        XCTAssertTrue(visible(element("card.checked")))
        tap("card.keep")
        XCTAssertTrue(element("share.preview").waitForExistence(timeout: 10))
        tap("share.close", down: false)
        XCTAssertTrue(app.staticTexts["card.title"].waitForExistence(timeout: 5))
    }

    func testRestrictedCardSourcesAndSharing() {
        launch()
        select("UNK", "FOO")
        XCTAssertEqual(app.staticTexts["card.title"].label, "Pause before cleaning")
        XCTAssertFalse(app.buttons["card.markChecked"].exists)
        tap("card.sources")
        XCTAssertTrue(visible(app.staticTexts["Follow the care instructions for your specific model first."]))
        tap("card.sources", down: false)
        tap("card.share")
        XCTAssertTrue(element("share.preview").waitForExistence(timeout: 10))
        tap("share.image")
        XCTAssertTrue(element("share.requested").waitForExistence(timeout: 10))
        tap("share.close", down: false)
        XCTAssertTrue(app.staticTexts["card.title"].waitForExistence(timeout: 5))
    }

    func testCopyAndExportCodeAndCancelPreview() {
        launch()
        select("W", "COF")
        tap("card.share")
        XCTAssertTrue(element("share.preview").waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["share.code"].label, "CSR1-W-COF")
        tap("share.copy")
        XCTAssertTrue(element("share.copied").waitForExistence(timeout: 5))
        tap("share.file")
        XCTAssertTrue(element("share.requested").waitForExistence(timeout: 10))
        tap("share.close", down: false)
        XCTAssertTrue(app.staticTexts["card.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(visible(app.buttons["card.markChecked"]))
    }

    func testThreeTapsExportImageDirectlyFromNewCard() {
        launch()
        select("W", "COF")
        tap("card.shareImage")
        XCTAssertTrue(element("share.requested").waitForExistence(timeout: 10))
        XCTAssertFalse(element("share.preview").exists)
        XCTAssertTrue(app.staticTexts["card.title"].exists)
    }

    func testThreeTapImportWithWhitespace() {
        launch(clipboard: " \tcsr1-ws-jui\n")
        tap("home.import")
        let field = app.textFields["import.code"]
        XCTAssertTrue(field.exists)
        let initialValue = field.value as? String ?? ""
        XCTAssertTrue(initialValue.isEmpty || initialValue == field.placeholderValue)
        XCTAssertFalse(app.buttons["import.use"].exists)
        tap("import.paste")
        XCTAssertTrue(app.staticTexts["import.match"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["import.match"].label.contains("WS"))
        tap("import.use")
        XCTAssertTrue(app.staticTexts["card.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["card.title"].label, "Fresh juice or wine spill")
    }

    func testInvalidImportPreservesPriorCardAndDoesNotOfferUse() {
        launch(clipboard: "CSR1-W-COF\nCSR1-X-COF")
        select("W", "COF")
        tap("card.home", down: false)
        tap("home.import")
        tap("import.paste")
        XCTAssertTrue(element("import.issue").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["import.use"].exists)
        XCTAssertTrue(app.buttons["import.file"].exists)
        tap("import.close", down: false)
        tap("home.resume")
        XCTAssertEqual(app.staticTexts["card.title"].label, "Fresh coffee or tea spill")
    }

    func testLegacyPaywallAndExpiryFlagsCannotChangePaidDownloadAccess() {
        launch(extra: ["-paywall", "-expired"])
        select("W", "COF")
        markChecked()
        tap("card.keep")
        XCTAssertTrue(element("share.preview").waitForExistence(timeout: 10))
    }

    func testMainButtonsHaveAtLeast44PointTargets() {
        launch()
        for id in ["home.import", "care.W", "care.LEA"] {
            let button = app.buttons[id]
            XCTAssertTrue(visible(button))
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
        select("W", "COF")
        for id in ["card.home", "card.change", "card.shareImage", "card.markChecked", "card.share"] {
            let button = app.buttons[id]
            XCTAssertTrue(visible(button))
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
    }

    func testStoreEnglish() throws { try captureStore(.en) }
    func testStoreSimplifiedChinese() throws { try captureStore(.hans) }
    func testStoreTraditionalChinese() throws { try captureStore(.hant) }

    private func captureStore(_ language: StoreLanguage) throws {
        launch(language: language)
        try shot("01-home", language)
        select("W", "COF")
        try shot("02-first-step", language)

        tap("card.change", down: false)
        tap("care.UNK")
        tap("card.change", down: false)
        tap("stain.FOO")
        try shot("03-stop", language)

        tap("card.home", down: false)
        select("W", "COF")
        markChecked()
        XCTAssertTrue(visible(element("card.checked")))
        try shot("04-recheck", language)
        tap("card.keep")
        XCTAssertTrue(element("share.preview").waitForExistence(timeout: 10))
        try shot("05-share", language)
    }

    private func launch(reset: Bool = true, language: StoreLanguage = .en, clipboard: String? = nil,
                        extra: [String] = []) {
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))",
                               "-AppleLocale", language.locale] + (reset ? ["-reset"] : []) + extra
        var environment: [String: String] = ["COUCHSTAIN_TEST_SESSION": session]
        if let clipboard { environment["COUCHSTAIN_TEST_PASTEBOARD"] = clipboard }
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 10))
    }

    private func markChecked() {
        tap("card.markChecked")
        XCTAssertTrue(visible(element("card.checked")))
    }

    private func select(_ care: String, _ stain: String) {
        tap("care." + care)
        tap("stain." + stain)
        XCTAssertTrue(app.staticTexts["card.title"].waitForExistence(timeout: 5))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func visible(_ element: XCUIElement, down: Bool = true) -> Bool {
        for attempt in 0...6 {
            if element.exists && element.isHittable { return true }
            if attempt < 6 {
                if down { app.swipeUp() } else { app.swipeDown() }
            }
        }
        return false
    }

    private func tap(_ id: String, down: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        XCTAssertTrue(visible(button, down: down), id, file: file, line: line)
        button.tap()
    }

    private func shot(_ scene: String, _ language: StoreLanguage) throws {
        let name = "store-\(language.rawValue)-\(scene)"
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let environment = ProcessInfo.processInfo.environment
        if let path = environment["SHOTS_DIR"] ?? environment["TEST_RUNNER_SHOTS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
            } catch {
            }
        }
    }
}
