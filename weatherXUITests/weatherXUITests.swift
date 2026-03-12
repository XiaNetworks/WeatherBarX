import XCTest

final class weatherXUITests: XCTestCase {
    func testAppLaunchesSuccessfully() {
        let app = makeApp()

        app.launch()

        XCTAssertTrue(app.buttons["status-item-button"].waitForExistence(timeout: 5))
    }

    func testMenuBarItemExists() {
        let app = makeApp()

        app.launch()

        XCTAssertTrue(app.buttons["status-item-button"].waitForExistence(timeout: 5))
    }

    func testClickingMenuBarItemOpensMenuPopover() {
        let app = makeApp()

        app.launch()
        app.buttons["status-item-button"].click()

        XCTAssertTrue(app.staticTexts["Placeholder weather"].waitForExistence(timeout: 5))
    }

    func testPlaceholderTextIsVisibleInDropdown() {
        let app = makeApp()

        app.launch()
        app.buttons["status-item-button"].click()

        XCTAssertTrue(app.staticTexts["Placeholder weather"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["72°"].waitForExistence(timeout: 5))
    }

    func testQuitActionClosesApp() {
        let app = makeApp()

        app.launch()
        app.buttons["status-item-button"].click()
        app.typeKey("q", modifierFlags: .command)

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        return app
    }
}
