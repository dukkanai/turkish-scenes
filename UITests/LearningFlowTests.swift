import XCTest

final class LearningFlowTests: XCTestCase {
    func testLearningScreenOpensAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DISABLE_VIDEO"]
        app.launch()
        XCTAssertTrue(app.navigationBars["لقطة تركية"].waitForExistence(timeout: 20))
        let first = app.buttons["segment-1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.contains("المقطع رقم"))
        XCTAssertTrue(first.label.contains("رئيس"))
        first.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "label BEGINSWITH %@", "المقطع")).firstMatch.waitForExistence(timeout: 10))
        let next = app.buttons["المقطع التالي"]
        for _ in 0..<15 {
            if next.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "label BEGINSWITH %@", "المقطع")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["متابعة التعلم"].waitForExistence(timeout: 10))
    }
}
