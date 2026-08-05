#if canImport(XCTest)
import XCTest
@testable import DouhuaPet

final class BehaviorTests: XCTestCase {
    func testWalkingTransitionsToObservationAfterItsDuration() {
        var behavior = PetBehaviorController(state: .walking, duration: 1)
        XCTAssertTrue(behavior.isMoving)
        XCTAssertNil(behavior.step(deltaTime: 0.5, choice: 0.2))
        XCTAssertEqual(behavior.step(deltaTime: 0.5, choice: 0.2), .observing)
        XCTAssertFalse(behavior.isMoving)
    }

    func testQuietStatesFavorLongerDurations() {
        XCTAssertGreaterThan(
            PetBehaviorController.duration(for: .sleeping, choice: 0),
            PetBehaviorController.duration(for: .walking, choice: 1)
        )
    }

    func testDeterministicQuietStateSequence() {
        var observing = PetBehaviorController(state: .observing, duration: 0)
        XCTAssertEqual(observing.step(deltaTime: 0, choice: 0.2), .loafing)

        var loafing = PetBehaviorController(state: .loafing, duration: 0)
        XCTAssertEqual(loafing.step(deltaTime: 0, choice: 0.2), .sleeping)

        var sleeping = PetBehaviorController(state: .sleeping, duration: 0)
        XCTAssertEqual(sleeping.step(deltaTime: 0, choice: 0.5), .observing)
    }

    func testFrameRatesReduceDuringRest() {
        XCTAssertEqual(PetBehaviorController.frameRate(for: .walking, quiet: false), 60)
        XCTAssertEqual(PetBehaviorController.frameRate(for: .observing, quiet: false), 8)
        XCTAssertEqual(PetBehaviorController.frameRate(for: .loafing, quiet: false), 6)
        XCTAssertEqual(PetBehaviorController.frameRate(for: .sleeping, quiet: false), 5)
        XCTAssertEqual(PetBehaviorController.frameRate(for: .walking, quiet: true), 5)
    }

    func testSpriteAssetMappingCoversEveryBehaviorState() {
        XCTAssertEqual(PetSpriteAsset.asset(for: .walking).rawValue, "douhua_walk_v1.png")
        XCTAssertEqual(PetSpriteAsset.asset(for: .observing).rawValue, "douhua_observe_v1.png")
        XCTAssertEqual(PetSpriteAsset.asset(for: .loafing).rawValue, "douhua_loaf_v1.png")
        XCTAssertEqual(PetSpriteAsset.asset(for: .sleeping).rawValue, "douhua_sleep_v1.png")
        XCTAssertEqual(PetSpriteAsset.petted.rawValue, "douhua_petted_v1.png")
        XCTAssertEqual(Set(PetSpriteAsset.allCases.map(\.rawValue)).count, 5)
    }
}
#endif
