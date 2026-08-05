import Foundation
import CoreGraphics

enum ScreenClamp {
    static func origin(_ origin: CGPoint, size: CGSize, inside bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }

    static func frame(_ frame: CGRect, inside bounds: CGRect) -> CGRect {
        CGRect(origin: origin(frame.origin, size: frame.size, inside: bounds), size: frame.size)
    }
}

struct HorizontalPatrol {
    private(set) var position: CGFloat
    private(set) var direction: CGFloat
    let speed: CGFloat
    let pauseDuration: TimeInterval
    private(set) var pauseRemaining: TimeInterval = 0
    var isPaused: Bool { pauseRemaining > 0 }

    init(position: CGFloat, direction: CGFloat, speed: CGFloat, pauseDuration: TimeInterval = 2) {
        self.position = position
        self.direction = direction < 0 ? -1 : 1
        self.speed = speed
        self.pauseDuration = pauseDuration
    }

    mutating func step(deltaTime: TimeInterval, range: ClosedRange<CGFloat>, pauseRequest: Bool) -> CGFloat {
        if pauseRequest && !isPaused { pauseRemaining = pauseDuration }
        if pauseRemaining > 0 {
            pauseRemaining = max(0, pauseRemaining - deltaTime)
            return position
        }
        position += direction * speed * deltaTime
        if position <= range.lowerBound {
            position = range.lowerBound
            direction = 1
        } else if position >= range.upperBound {
            position = range.upperBound
            direction = -1
        }
        return position
    }
}

/// Screen-space motion with gentle acceleration, deceleration, and a short turn pause.
///
/// `HorizontalPatrol` remains as the deterministic minimal primitive used by the
/// original tests. The app uses this controller so a realistic sprite does not look
/// like a static photograph sliding at constant speed.
struct NaturalPatrol {
    private(set) var position: CGFloat
    private(set) var velocity: CGFloat = 0
    private(set) var direction: CGFloat
    private(set) var turnPauseRemaining: TimeInterval = 0

    var maximumSpeed: CGFloat
    var acceleration: CGFloat
    var turnPauseDuration: TimeInterval

    init(
        position: CGFloat,
        direction: CGFloat,
        maximumSpeed: CGFloat,
        acceleration: CGFloat = 28,
        turnPauseDuration: TimeInterval = 1.1
    ) {
        self.position = position
        self.direction = direction < 0 ? -1 : 1
        self.maximumSpeed = max(0, maximumSpeed)
        self.acceleration = max(0, acceleration)
        self.turnPauseDuration = max(0, turnPauseDuration)
    }

    var isMoving: Bool { abs(velocity) > 0.05 }

    mutating func step(
        deltaTime: TimeInterval,
        range: ClosedRange<CGFloat>,
        active: Bool
    ) -> CGFloat {
        let dt = CGFloat(min(max(deltaTime, 0), 0.1))
        guard range.lowerBound <= range.upperBound else {
            position = range.lowerBound
            velocity = 0
            return position
        }

        position = min(max(position, range.lowerBound), range.upperBound)

        if turnPauseRemaining > 0 {
            turnPauseRemaining = max(0, turnPauseRemaining - deltaTime)
        }

        let targetVelocity: CGFloat = active && turnPauseRemaining <= 0
            ? direction * maximumSpeed
            : 0
        velocity = Self.approach(
            current: velocity,
            target: targetVelocity,
            maximumDelta: acceleration * dt
        )
        position += velocity * dt

        if position <= range.lowerBound {
            position = range.lowerBound
            if direction < 0 {
                direction = 1
                velocity = 0
                turnPauseRemaining = turnPauseDuration
            }
        } else if position >= range.upperBound {
            position = range.upperBound
            if direction > 0 {
                direction = -1
                velocity = 0
                turnPauseRemaining = turnPauseDuration
            }
        }
        return position
    }

    private static func approach(
        current: CGFloat,
        target: CGFloat,
        maximumDelta: CGFloat
    ) -> CGFloat {
        guard maximumDelta > 0 else { return current }
        if current < target { return min(current + maximumDelta, target) }
        if current > target { return max(current - maximumDelta, target) }
        return current
    }
}

struct CatHitRegion {
    let canvasSize: CGSize

    func contains(_ point: CGPoint) -> Bool {
        func ellipse(center: CGPoint, radius: CGSize) -> Bool {
            let dx = (point.x - center.x) / radius.width
            let dy = (point.y - center.y) / radius.height
            return dx * dx + dy * dy <= 1
        }
        return ellipse(center: CGPoint(x: canvasSize.width * 0.48, y: canvasSize.height * 0.48),
                       radius: CGSize(width: canvasSize.width * 0.34, height: canvasSize.height * 0.43))
            || ellipse(center: CGPoint(x: canvasSize.width * 0.76, y: canvasSize.height * 0.30),
                       radius: CGSize(width: canvasSize.width * 0.20, height: canvasSize.height * 0.18))
    }
}

struct DragActivation {
    let threshold: CGFloat
    private var startPoint: CGPoint?
    private(set) var isDragging = false

    init(threshold: CGFloat = 4) {
        self.threshold = max(0, threshold)
    }

    mutating func begin(at point: CGPoint) {
        startPoint = point
        isDragging = false
    }

    mutating func update(to point: CGPoint) -> Bool {
        guard let startPoint else { return false }
        if !isDragging {
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            isDragging = dx * dx + dy * dy >= threshold * threshold
        }
        return isDragging
    }

    mutating func end() {
        startPoint = nil
        isDragging = false
    }
}

enum PetBehaviorState: Equatable, Sendable {
    case walking
    case observing
    case loafing
    case sleeping
}

enum PetAnimationClipID: String, CaseIterable, Sendable {
    case walkLoop = "walk_loop"
    case observeIdle = "observe_idle"
    case loafBreathe = "loaf_breathe"
    case sleepBreathe = "sleep_breathe"
    case petObserve = "pet_observe"
    case petLoaf = "pet_loaf"
    case petSleep = "pet_sleep"
    case observeToWalk = "observe_to_walk"
    case walkToObserve = "walk_to_observe"
    case observeToLoaf = "observe_to_loaf"
    case loafToObserve = "loaf_to_observe"
    case loafToSleep = "loaf_to_sleep"
    case sleepToLoaf = "sleep_to_loaf"

    static func loop(for state: PetBehaviorState) -> Self {
        switch state {
        case .walking: .walkLoop
        case .observing: .observeIdle
        case .loafing: .loafBreathe
        case .sleeping: .sleepBreathe
        }
    }

    static func petResponse(for state: PetBehaviorState) -> Self? {
        switch state {
        case .walking: nil
        case .observing: .petObserve
        case .loafing: .petLoaf
        case .sleeping: .petSleep
        }
    }
}

struct PetAnimationTransition: Equatable, Sendable {
    let clip: PetAnimationClipID
    let from: PetBehaviorState
    let to: PetBehaviorState
}

enum PetTransitionPlanner {
    private static let states: [PetBehaviorState] = [
        .walking, .observing, .loafing, .sleeping,
    ]

    static func path(
        from source: PetBehaviorState,
        to target: PetBehaviorState
    ) -> [PetAnimationTransition] {
        guard source != target,
              let sourceIndex = states.firstIndex(of: source),
              let targetIndex = states.firstIndex(of: target) else { return [] }

        var result: [PetAnimationTransition] = []
        var index = sourceIndex
        while index != targetIndex {
            let nextIndex = index + (targetIndex > index ? 1 : -1)
            let from = states[index]
            let to = states[nextIndex]
            guard let clip = clip(from: from, to: to) else { return [] }
            result.append(PetAnimationTransition(clip: clip, from: from, to: to))
            index = nextIndex
        }
        return result
    }

    static func clip(
        from source: PetBehaviorState,
        to target: PetBehaviorState
    ) -> PetAnimationClipID? {
        switch (source, target) {
        case (.observing, .walking): .observeToWalk
        case (.walking, .observing): .walkToObserve
        case (.observing, .loafing): .observeToLoaf
        case (.loafing, .observing): .loafToObserve
        case (.loafing, .sleeping): .loafToSleep
        case (.sleeping, .loafing): .sleepToLoaf
        default: nil
        }
    }
}

/// A deterministic variable-duration frame clock used by the SpriteKit runtime.
/// It is kept platform-independent so seams, large time steps, and one-shots can
/// be tested without launching AppKit.
struct AnimationFrameClock: Equatable, Sendable {
    let durations: [TimeInterval]
    let loops: Bool
    private(set) var frameIndex = 0
    private(set) var elapsedInFrame: TimeInterval = 0
    private(set) var isComplete = false

    var currentDuration: TimeInterval {
        guard durations.indices.contains(frameIndex) else { return 0 }
        return durations[frameIndex]
    }

    var normalizedProgress: Double {
        guard currentDuration > 0 else { return 0 }
        return min(max(elapsedInFrame / currentDuration, 0), 1)
    }

    init(durations: [TimeInterval], loops: Bool) {
        self.durations = durations.map { max($0, 1.0 / 240.0) }
        self.loops = loops
        isComplete = durations.isEmpty
    }

    mutating func reset() {
        frameIndex = 0
        elapsedInFrame = 0
        isComplete = durations.isEmpty
    }

    /// Advances by monotonic elapsed time. The cap prevents a resume-from-sleep
    /// spiral while still allowing ordinary dropped render frames to catch up.
    @discardableResult
    mutating func advance(by deltaTime: TimeInterval, maximumSteps: Int = 32) -> Bool {
        guard !isComplete, !durations.isEmpty else { return false }
        elapsedInFrame += min(max(deltaTime, 0), 0.5)
        var changed = false
        var steps = 0
        while !isComplete,
              elapsedInFrame >= durations[frameIndex],
              steps < max(1, maximumSteps) {
            elapsedInFrame -= durations[frameIndex]
            steps += 1
            changed = true
            if frameIndex + 1 < durations.count {
                frameIndex += 1
            } else if loops {
                frameIndex = 0
            } else {
                frameIndex = durations.count - 1
                elapsedInFrame = 0
                isComplete = true
            }
        }
        return changed
    }
}

enum PetSpriteAsset: String, CaseIterable, Sendable {
    case walking = "douhua_walk_v1.png"
    case observing = "douhua_observe_v1.png"
    case loafing = "douhua_loaf_v1.png"
    case sleeping = "douhua_sleep_v1.png"
    case petted = "douhua_petted_v1.png"

    static let resourceDirectory = "Assets/Douhua/v1.0-realistic"

    static func asset(for state: PetBehaviorState) -> PetSpriteAsset {
        switch state {
        case .walking: .walking
        case .observing: .observing
        case .loafing: .loafing
        case .sleeping: .sleeping
        }
    }
}

struct PetBehaviorController {
    private(set) var state: PetBehaviorState
    private(set) var remaining: TimeInterval

    init(state: PetBehaviorState = .walking, duration: TimeInterval? = nil) {
        self.state = state
        remaining = duration ?? Self.duration(for: state, choice: 0.5)
    }

    var isMoving: Bool { state == .walking }

    static func duration(for state: PetBehaviorState, choice: Double) -> TimeInterval {
        let unit = min(max(choice, 0), 1)
        return switch state {
        case .walking: 6 + 4 * unit
        case .observing: 12 + 12 * unit
        case .loafing: 24 + 24 * unit
        case .sleeping: 50 + 40 * unit
        }
    }

    static func frameRate(for state: PetBehaviorState, quiet: Bool) -> Int {
        let normal = switch state {
        case .walking: 60
        case .observing: 8
        case .loafing: 6
        case .sleeping: 5
        }
        return quiet ? min(normal, 5) : normal
    }

    mutating func step(deltaTime: TimeInterval, choice: Double) -> PetBehaviorState? {
        remaining -= max(0, deltaTime)
        guard remaining <= 0 else { return nil }

        let unit = min(max(choice, 0), 1)
        switch state {
        case .walking:
            state = .observing
        case .observing:
            state = unit < 0.5 ? .loafing : (unit < 0.75 ? .walking : .sleeping)
        case .loafing:
            state = unit < 0.65 ? .sleeping : .observing
        case .sleeping:
            state = .observing
        }
        remaining = Self.duration(for: state, choice: unit)
        return state
    }
}
