import AppKit
import SpriteKit

enum PetClipRole: Equatable {
    case loop(PetBehaviorState)
    case transition(from: PetBehaviorState, to: PetBehaviorState)
    case pet(PetBehaviorState)
}

struct PetAnimationFrame {
    let texture: SKTexture
    let hitMask: SpriteHitMask
}

struct PetAnimationClip {
    let id: PetAnimationClipID
    let role: PetClipRole
    let frames: [PetAnimationFrame]
    let durations: [TimeInterval]

    var loops: Bool {
        if case .loop = role { return true }
        return false
    }
}

@MainActor
final class PetAnimationLibrary {
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let renderer: String
        let clips: [ManifestClip]
    }

    private struct ManifestClip: Decodable {
        let id: String
        let loops: Bool
        let frameCount: Int
        let files: [String]
        let durations: [TimeInterval]
    }

    private let bundle: Bundle
    private let manifestClips: [PetAnimationClipID: ManifestClip]
    private var clips: [PetAnimationClipID: PetAnimationClip] = [:]
    private var accessOrder: [PetAnimationClipID] = []
    private let maximumCachedClips = 1

    init?(bundle: Bundle) {
        self.bundle = bundle
        guard let manifestURL = bundle.url(
            forResource: "animation-manifest-v4",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
        manifest.schemaVersion == 4,
        manifest.renderer == "single-opaque-frame"
        else { return nil }

        var records: [PetAnimationClipID: ManifestClip] = [:]
        for record in manifest.clips {
            guard let id = PetAnimationClipID(rawValue: record.id),
                  record.loops == Self.role(for: id).isLoop,
                  record.frameCount == record.files.count,
                  record.files.count == record.durations.count,
                  !record.files.isEmpty,
                  record.durations.allSatisfy({ $0 > 0 })
            else { return nil }
            records[id] = record
        }

        // Validate all 312 paths without decoding their full RGBA payloads.
        for id in PetAnimationClipID.allCases {
            guard let record = records[id] else { return nil }
            for file in record.files {
                let url = URL(fileURLWithPath: file)
                guard bundle.url(
                    forResource: url.deletingPathExtension().lastPathComponent,
                    withExtension: url.pathExtension
                ) != nil else {
                    return nil
                }
            }
        }
        manifestClips = records
    }

    func clip(_ id: PetAnimationClipID) -> PetAnimationClip {
        if let cached = clips[id] {
            touch(id)
            return cached
        }

        guard let record = manifestClips[id] else {
            preconditionFailure("Validated animation clip disappeared: \(id.rawValue)")
        }
        var frames: [PetAnimationFrame] = []
        frames.reserveCapacity(record.files.count)
        for file in record.files {
            let resource = URL(fileURLWithPath: file)
            let stem = resource.deletingPathExtension().lastPathComponent
            guard let url = bundle.url(forResource: stem, withExtension: resource.pathExtension),
                  let image = NSImage(contentsOf: url),
                  let mask = SpriteHitMask(
                      image: image,
                      maximumDimension: 192,
                      alphaThreshold: 18
                  ) else {
                preconditionFailure("Validated animation frame became unreadable: \(file)")
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            frames.append(PetAnimationFrame(texture: texture, hitMask: mask))
        }
        let loaded = PetAnimationClip(
            id: id,
            role: Self.role(for: id),
            frames: frames,
            durations: record.durations
        )
        clips[id] = loaded
        touch(id)
        while accessOrder.count > maximumCachedClips {
            let evicted = accessOrder.removeFirst()
            clips.removeValue(forKey: evicted)
        }
        return loaded
    }

    private func touch(_ id: PetAnimationClipID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    /// v4 bakes stable loop anchors into transition and reaction endpoints, so
    /// playback never has to decode another clip just to replace a seam frame.
    func frame(for clip: PetAnimationClip, index: Int) -> PetAnimationFrame {
        let safeIndex = min(max(index, 0), clip.frames.count - 1)
        return clip.frames[safeIndex]
    }

    private static func role(for id: PetAnimationClipID) -> PetClipRole {
        switch id {
        case .walkLoop: .loop(.walking)
        case .observeIdle: .loop(.observing)
        case .loafBreathe: .loop(.loafing)
        case .sleepBreathe: .loop(.sleeping)
        case .petObserve: .pet(.observing)
        case .petLoaf: .pet(.loafing)
        case .petSleep: .pet(.sleeping)
        case .observeToWalk: .transition(from: .observing, to: .walking)
        case .walkToObserve: .transition(from: .walking, to: .observing)
        case .observeToLoaf: .transition(from: .observing, to: .loafing)
        case .loafToObserve: .transition(from: .loafing, to: .observing)
        case .loafToSleep: .transition(from: .loafing, to: .sleeping)
        case .sleepToLoaf: .transition(from: .sleeping, to: .loafing)
        }
    }

}

private extension PetClipRole {
    var isLoop: Bool {
        if case .loop = self { return true }
        return false
    }
}

struct PetAnimationSnapshot: Equatable {
    let clipID: PetAnimationClipID
    let frameIndex: Int
    let stableState: PetBehaviorState
    let desiredState: PetBehaviorState
    let generation: UInt64
}

@MainActor
final class PetAnimationDirector {
    private let library: PetAnimationLibrary
    private var clip: PetAnimationClip
    private var clock: AnimationFrameClock
    private var transitionRequested = false
    private var pendingPet = false
    private(set) var generation: UInt64 = 0
    private(set) var stableState: PetBehaviorState = .observing
    private(set) var desiredState: PetBehaviorState = .observing

    init(library: PetAnimationLibrary) {
        self.library = library
        let initial = library.clip(.observeIdle)
        clip = initial
        clock = AnimationFrameClock(durations: initial.durations, loops: true)
    }

    var snapshot: PetAnimationSnapshot {
        PetAnimationSnapshot(
            clipID: clip.id,
            frameIndex: clock.frameIndex,
            stableState: stableState,
            desiredState: desiredState,
            generation: generation
        )
    }

    var currentFrame: PetAnimationFrame {
        library.frame(for: clip, index: clock.frameIndex)
    }

    var locomotionIsActive: Bool {
        stableState == .walking
            && desiredState == .walking
            && clip.id == .walkLoop
    }

    var canTurnWithoutSliding: Bool {
        clip.id != .walkLoop
            || clock.frameIndex == 0
            || clock.frameIndex == clip.frames.count / 2
    }

    func requestState(_ state: PetBehaviorState) {
        desiredState = state
        guard state != stableState else {
            if case .loop = clip.role { transitionRequested = false }
            return
        }
        transitionRequested = true
        if case .loop = clip.role, isSafeExitFrame {
            beginNextTransition()
        }
    }

    func requestPet() {
        pendingPet = true
        if stableState == .walking {
            desiredState = .observing
            transitionRequested = true
            if case .loop = clip.role, isSafeExitFrame {
                beginNextTransition()
            }
            return
        }
        guard case .loop = clip.role,
              let petClip = PetAnimationClipID.petResponse(for: stableState) else { return }
        pendingPet = false
        start(petClip)
    }

    @discardableResult
    func update(deltaTime: TimeInterval) -> Bool {
        let oldClip = clip.id
        let oldFrame = clock.frameIndex
        let changed = clock.advance(by: deltaTime)

        if clock.isComplete {
            finishCurrentClip()
            return true
        }

        if changed,
           transitionRequested,
           case .loop = clip.role,
           isSafeExitFrame {
            beginNextTransition()
            return true
        }
        return oldClip != clip.id || oldFrame != clock.frameIndex
    }

    private func start(_ id: PetAnimationClipID) {
        let nextClip = library.clip(id)
        // Decode the destination loop before the body starts moving. If disk
        // work is needed, it extends the source anchor hold instead of causing
        // a hitch on the last transition frame.
        if case let .transition(_, to) = nextClip.role {
            _ = library.clip(.loop(for: to))
        }
        clip = nextClip
        clock = AnimationFrameClock(durations: clip.durations, loops: clip.loops)
        generation &+= 1
    }

    private var isSafeExitFrame: Bool {
        switch clip.id {
        case .walkLoop:
            clock.frameIndex == 0 || clock.frameIndex == clip.frames.count / 2
        case .observeIdle, .loafBreathe, .sleepBreathe:
            clock.frameIndex == 0 || clock.frameIndex == clip.frames.count - 1
        default:
            false
        }
    }

    private func beginNextTransition() {
        guard let edge = PetTransitionPlanner.path(
            from: stableState,
            to: desiredState
        ).first else {
            transitionRequested = false
            start(.loop(for: stableState))
            return
        }
        transitionRequested = false
        start(edge.clip)
    }

    private func finishCurrentClip() {
        switch clip.role {
        case let .transition(_, to):
            stableState = to
            if stableState != desiredState {
                beginNextTransition()
            } else if pendingPet,
                      let petClip = PetAnimationClipID.petResponse(for: stableState) {
                pendingPet = false
                start(petClip)
            } else {
                start(.loop(for: stableState))
            }
        case .pet:
            pendingPet = false
            if stableState != desiredState {
                beginNextTransition()
            } else {
                start(.loop(for: stableState))
            }
        case .loop:
            start(.loop(for: stableState))
        }
    }
}
