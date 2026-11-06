import XCTest

final class LearningFlowTests: XCTestCase {
    func testNewCurriculumAndResumeWithoutPaidConnection() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["تعلّم التركية"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["segment-1"].exists)
        app.buttons["audio-track-word"].tap()
        let first = app.buttons["audio-lesson-word-lesson-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.navigationBars["درسي الصوتي"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["audio-paid-start"].exists)
        app.buttons["audio-paid-start"].tap()
        XCTAssertTrue(app.alerts["بدء جلسة مدفوعة؟"].waitForExistence(timeout: 5))
        app.alerts.buttons["إلغاء"].tap()
        XCTAssertEqual(app.staticTexts["audio-status"].value as? String, "متوقفة")
        XCTAssertTrue(app.buttons["audio-paid-start"].isEnabled)
        XCTAssertFalse(app.buttons["إيقاف الجلسة والميكروفون"].exists)
        app.buttons["إغلاق"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["audio-resume"].waitForExistence(timeout: 10))
        app.tabBars.buttons["تقدمي"].tap()
        app.buttons["audio-settings"].tap()
        XCTAssertTrue(app.secureTextFields["audio-key-input"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["حفظ المفتاح بأمان"].isEnabled)
    }
}
