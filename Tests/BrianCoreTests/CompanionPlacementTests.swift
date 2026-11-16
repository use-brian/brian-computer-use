import XCTest
@testable import BrianCore

final class CompanionPlacementTests: XCTestCase {
    func testReturnToSideUsesRestingSideAndClampsToDisplay() {
        let screen = CGRect(x: -1440, y: 25, width: 1440, height: 850)
        let size = CGSize(width: 146, height: 138)
        let left = CompanionPlacement.atSide(CGRect(x: -1300, y: 300, width: 146, height: 138), size: size, screen: screen)
        XCTAssertEqual(left.minX, screen.minX + 20)
        XCTAssertEqual(left.minY, 300)
        let right = CompanionPlacement.atSide(CGRect(x: -200, y: 900, width: 146, height: 138), size: size, screen: screen)
        XCTAssertEqual(right.maxX, screen.maxX - 20)
        XCTAssertTrue(screen.contains(right))
    }

    func testTargetNearLeftEdgeUsesUnobstructedSide() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let target = CGRect(x: 4, y: 400, width: 90, height: 32)
        let result = CompanionPlacement.beside(target, size: CGSize(width: 64, height: 64), screen: screen)
        XCTAssertTrue(screen.contains(result))
        XCTAssertFalse(result.intersects(target))
        XCTAssertGreaterThan(result.minX, target.maxX)
    }
    func testNegativeDisplayCoordinatesAndCornerTargets() {
        let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        for target in [CGRect(x: -1920, y: -300, width: 45, height: 25),
                       CGRect(x: -45, y: 755, width: 45, height: 25)] {
            let result = CompanionPlacement.beside(target, size: CGSize(width: 64, height: 64), screen: screen)
            XCTAssertTrue(screen.contains(result))
            XCTAssertFalse(result.intersects(target))
        }
    }
    func testBarNearTopPlacesPetBelowWithoutCoveringInput() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 875)
        let bar = CGRect(x: -1000, y: 790, width: 620, height: 64)
        let result = CompanionPlacement.byBar(bar, size: CGSize(width: 146, height: 138), screen: screen)
        XCTAssertTrue(screen.contains(result))
        XCTAssertFalse(result.intersects(bar))
        XCTAssertLessThan(result.maxY, bar.minY)
    }
    func testMovementIgnoresWindowSizedMissingAndOffscreenTargets() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        for invalid in [screen, .zero, .null, CGRect(x: 200, y: 100, width: 80, height: 30),
                        CGRect(x: CGFloat.nan, y: 10, width: 30, height: 20)] {
            XCTAssertNil(CompanionPlacement.visibleTarget(invalid, screen: screen))
        }
        let partiallyVisible = CGRect(x: -1460, y: 200, width: 400, height: 80)
        XCTAssertEqual(CompanionPlacement.visibleTarget(partiallyVisible, screen: screen),
                       CGRect(x: -1440, y: 200, width: 380, height: 80))
    }

}
