#if canImport(XCTest)
import XCTest
@testable import DouhuaPet

final class GeometryTests: XCTestCase {
    private let visible = CGRect(x: 100, y: 50, width: 800, height: 600)
    private let size = CGSize(width: 180, height: 220)

    func testClampOriginAtEveryEdge() {
        XCTAssertEqual(
            ScreenClamp.origin(CGPoint(x: 0, y: 0), size: size, inside: visible),
            CGPoint(x: 100, y: 50)
        )
        XCTAssertEqual(
            ScreenClamp.origin(CGPoint(x: 950, y: 700), size: size, inside: visible),
            CGPoint(x: 720, y: 430)
        )
        XCTAssertEqual(
            ScreenClamp.origin(CGPoint(x: 200, y: 300), size: size, inside: visible),
            CGPoint(x: 200, y: 300)
        )
    }

    func testClampFrameLargerThanVisibleFrame() {
        let result = ScreenClamp.frame(
            CGRect(x: -10, y: -20, width: 1_000, height: 700),
            inside: visible
        )
        XCTAssertEqual(result.origin, visible.origin)
    }

    func testHitRegionInsideAndOutside() {
        let region = CatHitRegion(canvasSize: CGSize(width: 180, height: 220))
        XCTAssertTrue(region.contains(CGPoint(x: 90, y: 110)))
        XCTAssertTrue(region.contains(CGPoint(x: 145, y: 65)))
        XCTAssertFalse(region.contains(CGPoint(x: 5, y: 210)))
        XCTAssertFalse(region.contains(CGPoint(x: 175, y: 215)))
    }

    func testClickDoesNotActivateDragUntilThreshold() {
        var gesture = DragActivation(threshold: 4)
        gesture.begin(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(gesture.update(to: CGPoint(x: 12, y: 12)))
        XCTAssertFalse(gesture.isDragging)
        XCTAssertTrue(gesture.update(to: CGPoint(x: 14, y: 10)))
        XCTAssertTrue(gesture.isDragging)
        gesture.end()
        XCTAssertFalse(gesture.isDragging)
    }

    func testPatrolBouncesAtBothEdges() {
        var lower = HorizontalPatrol(position: 5, direction: -1, speed: 10)
        XCTAssertEqual(lower.step(deltaTime: 1, range: 0...100, pauseRequest: false), 0)
        XCTAssertEqual(lower.direction, 1)

        var upper = HorizontalPatrol(position: 98, direction: 1, speed: 10)
        XCTAssertEqual(upper.step(deltaTime: 1, range: 0...100, pauseRequest: false), 100)
        XCTAssertEqual(upper.direction, -1)
    }

    func testPatrolPauseAndResume() {
        var patrol = HorizontalPatrol(position: 50, direction: 1, speed: 10, pauseDuration: 2)
        XCTAssertEqual(patrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: true), 50)
        XCTAssertTrue(patrol.isPaused)
        XCTAssertEqual(patrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 50)
        XCTAssertEqual(patrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 50)
        XCTAssertFalse(patrol.isPaused)
        XCTAssertEqual(patrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: false), 55)
    }
}
#endif
