import XCTest
@testable import BrianCore

final class CompanionPlacementTests: XCTestCase {
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
}
