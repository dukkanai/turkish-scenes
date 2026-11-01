import XCTest

final class LearningFlowTests: XCTestCase {
    func testLearningScreenOpensAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DISABLE_VIDEO"]
        app.launch()
        XCTAssertTrue(app.navigationBars["لقطة تركية"].waitForExistence(timeout: 20))
        let first = app.buttons["segment-1"].firstMatch
        let found = first.waitForExistence(timeout: 10)
        if !found { print(String(app.debugDescription.prefix(16000))) }
        XCTAssertTrue(found)
        guard found else { return }
        XCTAssertTrue(first.label.contains("المقطع رقم"))
        XCTAssertTrue(first.label.contains("رئيس"))
        first.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "label BEGINSWITH %@", "المقطع")).firstMatch.waitForExistence(timeout: 10), String(app.debugDescription.prefix(12000)))
        let initialTitle = app.navigationBars.matching(NSPredicate(format: "label BEGINSWITH %@", "المقطع")).firstMatch.label
        let next = app.buttons["المقطع التالي"]
        for _ in 0..<15 {
            if next.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "label BEGINSWITH %@", "المقطع")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertNotEqual(initialTitle, app.navigationBars.matching(NSPredicate(format: "label BEGINSWITH %@", "المقطع")).firstMatch.label)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["متابعة التعلم"].waitForExistence(timeout: 10))
    }
}
