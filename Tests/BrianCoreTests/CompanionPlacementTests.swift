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

    func testCursorTipStaysOnTargetAcrossDisplaysAndCorners() throws {
        for screen in [CGRect(x: 0, y: 25, width: 1512, height: 900),
                       CGRect(x: -1920, y: -300, width: 1920, height: 1080)] {
            for point in [CGPoint(x: screen.minX + 1, y: screen.minY + 1),
                          CGPoint(x: screen.maxX - 1, y: screen.minY + 1),
                          CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),
                          CGPoint(x: screen.minX + 1, y: screen.maxY - 1),
                          CGPoint(x: screen.midX, y: screen.midY)] {
                let cursor = try XCTUnwrap(CompanionPlacement.cursor(at: point, screen: screen))
                XCTAssertEqual(cursor.frame.midX, point.x)
                XCTAssertEqual(cursor.frame.midY, point.y)
                // The badge remains inside the screen while the tip never shifts.
                let badge = CGPoint(x: point.x + (cursor.flipX ? -17 : 17),
                                    y: point.y + (cursor.flipY ? 20 : -20))
                XCTAssertTrue(screen.contains(CGRect(x: badge.x - 8, y: badge.y - 8, width: 16, height: 16)))
            }
        }
    }
    func testCursorRejectsOffscreenAndInvalidPoints() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertNil(CompanionPlacement.cursor(at: CGPoint(x: -1, y: 200), screen: screen))
        XCTAssertNil(CompanionPlacement.cursor(at: CGPoint(x: CGFloat.nan, y: 200), screen: screen))
    }

    func testClippingNeverChangesTheIndicatedActionPoint() throws {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visionTarget = CGRect(x: -10, y: 100, width: 24, height: 24)
        XCTAssertEqual(CompanionPlacement.cursorTarget(visionTarget, screen: screen), visionTarget)
        XCTAssertEqual(try XCTUnwrap(CompanionPlacement.cursorTarget(visionTarget, screen: screen)).midX, 2)
        XCTAssertNil(CompanionPlacement.cursorTarget(CGRect(x: -30, y: 100, width: 40, height: 20), screen: screen))
    }

}
