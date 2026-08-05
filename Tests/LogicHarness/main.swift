import Foundation

struct CheckRunner {
    private(set) var failures = 0
    private(set) var total = 0

    mutating func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        total += 1
        if condition() {
            print("PASS: \(name)")
        } else {
            failures += 1
            fputs("FAIL: \(name)\n", stderr)
        }
    }

    mutating func checkClose(_ actual: CGFloat, _ expected: CGFloat, _ name: String) {
        check(abs(actual - expected) < 0.001, name)
    }
}

var checks = CheckRunner()
let visible = CGRect(x: 100, y: 50, width: 800, height: 600)
let size = CGSize(width: 180, height: 220)

checks.check(ScreenClamp.origin(CGPoint(x: 0, y: 0), size: size, inside: visible) == CGPoint(x: 100, y: 50), "clamp lower edges")
checks.check(ScreenClamp.origin(CGPoint(x: 950, y: 700), size: size, inside: visible) == CGPoint(x: 720, y: 430), "clamp upper edges")
checks.check(ScreenClamp.origin(CGPoint(x: 200, y: 300), size: size, inside: visible) == CGPoint(x: 200, y: 300), "preserve in-bounds origin")
checks.check(ScreenClamp.frame(CGRect(x: -10, y: -20, width: 1_000, height: 700), inside: visible).origin == visible.origin, "oversize frame anchors to visible origin")

let hitRegion = CatHitRegion(canvasSize: CGSize(width: 180, height: 220))
checks.check(hitRegion.contains(CGPoint(x: 90, y: 110)), "body hit region")
checks.check(hitRegion.contains(CGPoint(x: 145, y: 65)), "tail hit region")
checks.check(!hitRegion.contains(CGPoint(x: 5, y: 210)), "top-left transparent region")
checks.check(!hitRegion.contains(CGPoint(x: 175, y: 215)), "top-right transparent region")

var patrol = HorizontalPatrol(position: 5, direction: -1, speed: 10)
checks.checkClose(patrol.step(deltaTime: 0.2, range: 0...100, pauseRequest: false), 3, "patrol advances left")
checks.checkClose(patrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 0, "patrol clamps at lower bound")
checks.check(patrol.direction == 1, "patrol reverses at lower bound")
checks.checkClose(patrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: false), 5, "patrol advances after reversal")

var upperPatrol = HorizontalPatrol(position: 98, direction: 1, speed: 10)
checks.checkClose(upperPatrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 100, "patrol clamps at upper bound")
checks.check(upperPatrol.direction == -1, "patrol reverses at upper bound")

var pausedPatrol = HorizontalPatrol(position: 50, direction: 1, speed: 10, pauseDuration: 2)
checks.checkClose(pausedPatrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: true), 50, "explicit pause starts without movement")
checks.check(pausedPatrol.isPaused, "pause state is visible")
checks.checkClose(pausedPatrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 50, "pause holds position")
checks.checkClose(pausedPatrol.step(deltaTime: 1, range: 0...100, pauseRequest: false), 50, "pause expires without an extra move")
checks.check(!pausedPatrol.isPaused, "pause expires deterministically")
checks.checkClose(pausedPatrol.step(deltaTime: 0.5, range: 0...100, pauseRequest: false), 55, "patrol resumes after pause")

var naturalMotion = NaturalPatrol(position: 50, direction: -1, maximumSpeed: 20, acceleration: 10)
checks.checkClose(naturalMotion.step(deltaTime: 0.1, range: 0...100, active: true), 49.9, "natural patrol accelerates rather than jumps to full speed")
checks.checkClose(naturalMotion.velocity, -1, "natural patrol exposes eased velocity")
checks.checkClose(naturalMotion.step(deltaTime: 0.1, range: 0...100, active: false), 49.9, "natural patrol decelerates to a stop")
checks.checkClose(naturalMotion.velocity, 0, "natural patrol stops without residual drift")

var naturalEdge = NaturalPatrol(position: 0.05, direction: -1, maximumSpeed: 20, acceleration: 100)
checks.checkClose(naturalEdge.step(deltaTime: 0.1, range: 0...100, active: true), 0, "natural patrol clamps at the edge")
checks.check(naturalEdge.direction == 1, "natural patrol turns toward the visible area")
checks.check(naturalEdge.turnPauseRemaining > 0, "natural patrol pauses briefly after turning")

var clickGesture = DragActivation(threshold: 4)
clickGesture.begin(at: CGPoint(x: 10, y: 10))
checks.check(!clickGesture.update(to: CGPoint(x: 12, y: 12)), "small pointer movement remains a click")
checks.check(!clickGesture.isDragging, "click does not activate dragging")
clickGesture.end()

var dragGesture = DragActivation(threshold: 4)
dragGesture.begin(at: CGPoint(x: 10, y: 10))
checks.check(dragGesture.update(to: CGPoint(x: 14, y: 10)), "threshold movement activates dragging")
checks.check(dragGesture.isDragging, "drag activation state is visible")
checks.check(dragGesture.update(to: CGPoint(x: 12, y: 10)), "active drag remains active after moving back")
dragGesture.end()
checks.check(!dragGesture.isDragging, "ending a gesture resets dragging")

var behavior = PetBehaviorController(state: .walking, duration: 1)
checks.check(behavior.state == .walking, "behavior starts in requested state")
checks.check(behavior.isMoving, "walking behavior allows patrol movement")
checks.check(behavior.step(deltaTime: 0.5, choice: 0.2) == nil, "behavior holds before duration expires")
checks.check(behavior.step(deltaTime: 0.5, choice: 0.2) == .observing, "walking transitions to observing")
checks.check(!behavior.isMoving, "observing behavior stops patrol movement")
checks.check(PetBehaviorController.duration(for: .sleeping, choice: 0) > PetBehaviorController.duration(for: .walking, choice: 1), "sleeping lasts longer than walking")

var observing = PetBehaviorController(state: .observing, duration: 0)
checks.check(observing.step(deltaTime: 0, choice: 0.2) == .loafing, "quiet observation usually transitions to loafing")
var loafing = PetBehaviorController(state: .loafing, duration: 0)
checks.check(loafing.step(deltaTime: 0, choice: 0.2) == .sleeping, "loafing usually transitions to sleeping")
var sleeping = PetBehaviorController(state: .sleeping, duration: 0)
checks.check(sleeping.step(deltaTime: 0, choice: 0.5) == .observing, "sleeping wakes into observation")
checks.check(PetBehaviorController.frameRate(for: .walking, quiet: false) == 60, "walking keeps 60 FPS")
checks.check(PetBehaviorController.frameRate(for: .observing, quiet: false) == 8, "observation reduces to 8 FPS")
checks.check(PetBehaviorController.frameRate(for: .loafing, quiet: false) == 6, "loafing reduces to 6 FPS")
checks.check(PetBehaviorController.frameRate(for: .sleeping, quiet: false) == 5, "sleeping reduces to 5 FPS")
checks.check(PetBehaviorController.frameRate(for: .walking, quiet: true) == 5, "quiet mode caps updates at 5 FPS")
checks.check(PetSpriteAsset.asset(for: .walking) == .walking, "walking maps to walking sprite")
checks.check(PetSpriteAsset.asset(for: .observing) == .observing, "observing maps to observing sprite")
checks.check(PetSpriteAsset.asset(for: .loafing) == .loafing, "loafing maps to loafing sprite")
checks.check(PetSpriteAsset.asset(for: .sleeping) == .sleeping, "sleeping maps to sleeping sprite")
checks.check(PetSpriteAsset.petted.rawValue == "douhua_petted_v1.png", "petting maps to the realistic response sprite")
checks.check(PetSpriteAsset.allCases.map(\.rawValue).allSatisfy { $0.hasPrefix("douhua_") && $0.hasSuffix(".png") }, "sprite filenames use packaged png assets")

let sleepRoute = PetTransitionPlanner.path(from: .walking, to: .sleeping)
checks.check(
    sleepRoute.map(\.clip) == [.walkToObserve, .observeToLoaf, .loafToSleep],
    "walking reaches sleep through three physical transitions"
)
let wakeRoute = PetTransitionPlanner.path(from: .sleeping, to: .walking)
checks.check(
    wakeRoute.map(\.clip) == [.sleepToLoaf, .loafToObserve, .observeToWalk],
    "sleep reaches walking through distinct wake-up transitions"
)
checks.check(
    PetTransitionPlanner.path(from: .observing, to: .observing).isEmpty,
    "stable state never schedules a redundant transition"
)
checks.check(
    PetAnimationClipID.loop(for: .loafing) == .loafBreathe
        && PetAnimationClipID.petResponse(for: .sleeping) == .petSleep,
    "stable poses map to their continuous loop and reaction clips"
)

var loopingClock = AnimationFrameClock(durations: [0.1, 0.2, 0.3], loops: true)
checks.check(!loopingClock.advance(by: 0.09) && loopingClock.frameIndex == 0, "frame clock holds until its duration")
checks.check(abs(loopingClock.normalizedProgress - 0.9) < 0.001, "frame clock exposes normalized frame progress")
checks.check(loopingClock.advance(by: 0.02) && loopingClock.frameIndex == 1, "frame clock carries fractional elapsed time")
checks.check(abs(loopingClock.currentDuration - 0.2) < 0.001, "frame clock exposes the active variable duration")
checks.check(loopingClock.advance(by: 0.20) && loopingClock.frameIndex == 2, "frame clock supports variable frame durations")
checks.check(loopingClock.advance(by: 0.30) && loopingClock.frameIndex == 0, "loop seam returns to the anchor frame")
var oneShotClock = AnimationFrameClock(durations: [0.1, 0.1], loops: false)
checks.check(oneShotClock.advance(by: 0.25), "one-shot clock advances across more than one frame")
checks.check(oneShotClock.isComplete && oneShotClock.frameIndex == 1, "one-shot clock stops on its final frame")
oneShotClock.reset()
checks.check(!oneShotClock.isComplete && oneShotClock.frameIndex == 0, "one-shot clock resets deterministically")

let settingsSuite = "DouhuaPet.LogicHarness.\(UUID().uuidString)"
if let defaults = UserDefaults(suiteName: settingsSuite) {
    defaults.removePersistentDomain(forName: settingsSuite)
    let store = PetSettingsStore(defaults: defaults)
    checks.check(!store.quiet && !store.hidden && !store.paused, "settings use safe disabled mode defaults")
    checks.check(store.size == .medium && store.activity == .quiet, "settings use medium and quiet product defaults")
    store.quiet = true
    store.size = .large
    store.activity = .active
    store.savePosition(normalizedX: -1, normalizedY: 2, screenIdentifier: " display-main ")
    let restored = PetSettingsStore(defaults: defaults)
    checks.check(restored.quiet && restored.size == .large && restored.activity == .active, "settings persist across store instances")
    checks.check(restored.normalizedX == 0 && restored.normalizedY == 1, "persisted coordinates are clamped")
    checks.check(restored.screenIdentifier == "display-main", "screen identifier is sanitized")
    restored.reset()
    checks.check(!restored.quiet && restored.size == .medium && restored.screenIdentifier == nil, "settings reset removes persisted values")
    defaults.removePersistentDomain(forName: settingsSuite)
} else {
    checks.check(false, "create isolated settings defaults suite")
}

if checks.failures > 0 {
    fputs("FAILED: \(checks.failures) of \(checks.total) logic checks\n", stderr)
    exit(1)
}

print("ALL PASS: \(checks.total) logic checks")
