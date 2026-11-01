import XCTest

final class LearningFlowTests: XCTestCase {
    func testLearningScreenOpensAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DISABLE_VIDEO"]
        app.launch()
        XCTAssertTrue(app.navigationBars["لقطة تركية"].waitForExistence(timeout: 20))
        let first = app.staticTexts["المقطع 1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.navigationBars["المقطع 1"].waitForExistence(timeout: 10))
        let next = app.buttons["المقطع التالي"]
        for _ in 0..<15 {
            if next.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.navigationBars["المقطع 2"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["متابعة التعلم"].waitForExistence(timeout: 10))
    }
}
