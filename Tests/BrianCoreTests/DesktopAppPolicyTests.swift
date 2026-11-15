import XCTest
@testable import BrianCore

final class DesktopAppPolicyTests: XCTestCase {
    func testProductionExcludesKnownAndMarkedFixturesButKeepsRealApps() {
        XCTAssertFalse(DesktopAppPolicy.allows(bundleID: "com.usebrian.WorkflowTest"))
        XCTAssertFalse(DesktopAppPolicy.allows(bundleID: "com.usebrian.NavigationDemo"))
        XCTAssertFalse(DesktopAppPolicy.allows(bundleID: "future.fixture", markedAsTestFixture: true))
        XCTAssertTrue(DesktopAppPolicy.allows(bundleID: "com.apple.mail"))
        XCTAssertTrue(DesktopAppPolicy.allows(bundleID: "com.apple.TextEdit"))
    }
    func testDeveloperFixtureAccessRequiresExplicitOptIn() {
        XCTAssertTrue(DesktopAppPolicy.allows(bundleID: "com.usebrian.WorkflowTest", allowTestFixtures: true))
        XCTAssertTrue(DesktopAppPolicy.allows(bundleID: "future.fixture", markedAsTestFixture: true, allowTestFixtures: true))
    }
}
