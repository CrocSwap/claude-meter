//
//  ClaudeMeterUITests.swift
//  ClaudeMeterUITests
//
//  Created by Douglas Colkitt on 4/30/26.
//

import XCTest

final class ClaudeMeterUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testAppLaunchesWithoutCrashing() throws {
        let app = XCUIApplication()
        app.launch()
        // LSUIElement apps have no main window; reaching this point without an
        // exception is the smoke-test bar. Real menu-bar UI assertions land in
        // task #8 once SignInView / UsagePopover exist.
    }
}
