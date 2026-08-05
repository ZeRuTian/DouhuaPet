#if canImport(XCTest)
import XCTest
@testable import DouhuaPet

final class PatrolTests: XCTestCase {
    func testMovesAndBouncesDeterministically() {
        var patrol = HorizontalPatrol(position: 5, direction: -1, speed: 10)
        XCTAssertEqual(patrol.step(deltaTime: 0.2, range: 0...100, pauseRequest: false), 3, accuracy: 0.001)
        XCTAssertEqual(patrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 0, accuracy: 0.001)
        XCTAssertEqual(patrol.direction, 1)
        XCTAssertEqual(patrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: false), 5, accuracy: 0.001)
    }

    func testExplicitPauseRequestAndResume() {
        var patrol = HorizontalPatrol(position: 50, direction: 1, speed: 10, pauseDuration: 2)
        XCTAssertEqual(patrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: true), 50)
        XCTAssertTrue(patrol.isPaused)
        XCTAssertEqual(patrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 50)
        XCTAssertEqual(patrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 50)
        XCTAssertFalse(patrol.isPaused)
        XCTAssertEqual(patrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: false), 55)
    }

    func testNaturalPatrolAcceleratesDeceleratesAndTurns() {
        var motion = NaturalPatrol(
            position: 50,
            direction: -1,
            maximumSpeed: 20,
            acceleration: 10,
            turnPauseDuration: 1
        )
        XCTAssertEqual(motion.step(deltaTime: 0.1, range: 0...100, active: true), 49.9, accuracy: 0.001)
        XCTAssertEqual(motion.velocity, -1, accuracy: 0.001)
        XCTAssertEqual(motion.step(deltaTime: 0.1, range: 0...100, active: false), 49.9, accuracy: 0.001)
        XCTAssertEqual(motion.velocity, 0, accuracy: 0.001)

        var edge = NaturalPatrol(
            position: 0.05,
            direction: -1,
            maximumSpeed: 20,
            acceleration: 100,
            turnPauseDuration: 1
        )
        XCTAssertEqual(edge.step(deltaTime: 0.1, range: 0...100, active: true), 0, accuracy: 0.001)
        XCTAssertEqual(edge.direction, 1)
        XCTAssertEqual(edge.velocity, 0, accuracy: 0.001)
        XCTAssertGreaterThan(edge.turnPauseRemaining, 0)
    }
}
#endif
