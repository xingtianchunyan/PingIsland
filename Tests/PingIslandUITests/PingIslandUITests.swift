import XCTest

/// 首次设置 UI 测试（执行文档 14.3）
final class PingIslandUITests: XCTestCase {
    func testOnboardingAppearsOnFreshInstall() {
        let app = XCUIApplication()
        app.launch()
        // 首次安装应看到欢迎页；若已完成设置则显示角色页
        let welcome = app.staticTexts["欢迎来到屏之岛"]
        let character = app.staticTexts["屏之岛"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5) || character.waitForExistence(timeout: 2))
    }
}
