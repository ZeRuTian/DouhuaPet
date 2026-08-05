import Foundation
import SceneKit
import SpriteKit
import simd

/// Loads one identity-stable, skinned Douhua mesh and drives all motion from a
/// semantic feline skeleton. The renderer is asset-independent: a production
/// USDZ can replace the model without changing behavior or interaction code.
@MainActor
final class Douhua3DController {
    private struct Manifest: Decodable {
        struct Camera: Decodable {
            let position: [Float]
            let target: [Float]
            let fieldOfView: CGFloat
        }

        let schemaVersion: Int
        let model: String
        let rootNode: String
        let modelScale: Float
        let modelYawDegrees: Float
        let camera: Camera
        let bones: [String: String]
    }

    let spriteNode: SK3DNode
    private let modelRoot: SCNNode
    private let poseDriver: FelineRigPoseDriver
    private var isPaused = false
    private var requestedState: PetBehaviorState = .observing

    static func load(bundle: Bundle, viewportSize: CGSize) -> Douhua3DController? {
        guard let manifestURL = bundle.url(
            forResource: "douhua-rig-v1",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
        manifest.schemaVersion == 1
        else { return nil }

        let modelURL = URL(fileURLWithPath: manifest.model)
        guard let resourceURL = bundle.url(
            forResource: modelURL.deletingPathExtension().lastPathComponent,
            withExtension: modelURL.pathExtension
        ),
        let sourceScene = try? SCNScene(url: resourceURL, options: nil),
        let sourceRoot = sourceScene.rootNode.childNode(
            withName: manifest.rootNode,
            recursively: true
        )
        else { return nil }

        let scene = SCNScene()
        let modelRoot = SCNNode()
        modelRoot.name = "douhua-model-container"
        modelRoot.simdScale = SIMD3<Float>(repeating: manifest.modelScale)
        modelRoot.simdEulerAngles.y = manifest.modelYawDegrees * .pi / 180
        sourceRoot.removeFromParentNode()
        modelRoot.addChildNode(sourceRoot)
        scene.rootNode.addChildNode(modelRoot)

        guard let poseDriver = FelineRigPoseDriver(
            modelRoot: modelRoot,
            boneNames: manifest.bones
        ) else { return nil }

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = manifest.camera.fieldOfView
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.simdPosition = manifest.camera.position.vector3
        cameraNode.look(
            at: manifest.camera.target.scnVector3,
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 920
        key.light?.temperature = 5_600
        key.simdEulerAngles = SIMD3<Float>(-0.75, 0.65, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 300
        fill.light?.temperature = 6_500
        fill.simdPosition = SIMD3<Float>(-2, 1.8, 2.5)
        scene.rootNode.addChildNode(fill)
        scene.lightingEnvironment.intensity = 0.55

        let node = SK3DNode(viewportSize: viewportSize)
        node.name = "douhua-rigged-3d"
        node.scnScene = scene
        node.pointOfView = cameraNode
        node.autoenablesDefaultLighting = false
        node.isPlaying = true
        node.loops = true
        node.position = CGPoint(x: 0, y: viewportSize.height * 0.5)
        return Douhua3DController(
            spriteNode: node,
            modelRoot: modelRoot,
            poseDriver: poseDriver
        )
    }

    private init(
        spriteNode: SK3DNode,
        modelRoot: SCNNode,
        poseDriver: FelineRigPoseDriver
    ) {
        self.spriteNode = spriteNode
        self.modelRoot = modelRoot
        self.poseDriver = poseDriver
        poseDriver.requestState(.observing, transitionDuration: 0)
    }

    func resize(to size: CGSize) {
        spriteNode.viewportSize = size
        spriteNode.position.y = size.height * 0.5
    }

    func requestState(_ state: PetBehaviorState) {
        guard state != requestedState else { return }
        requestedState = state
        let duration: TimeInterval = switch (poseDriver.state, state) {
        case (.walking, .observing), (.observing, .walking): 0.48
        case (.observing, .loafing), (.loafing, .observing): 0.82
        case (.loafing, .sleeping), (.sleeping, .loafing): 1.05
        default: 0.72
        }
        poseDriver.requestState(state, transitionDuration: duration)
    }

    func requestPet() {
        poseDriver.requestPet()
    }

    func setFacingRight(_ facingRight: Bool) {
        let base = facingRight ? Float.pi : 0
        poseDriver.setFacingYaw(base)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        spriteNode.isPlaying = !paused
    }

    func update(deltaTime: TimeInterval) {
        guard !isPaused else { return }
        poseDriver.update(deltaTime: deltaTime)
    }
}

@MainActor
private final class FelineRigPoseDriver {
    private struct Bone {
        let node: SCNNode
        let restOrientation: simd_quatf
    }

    private struct Pose {
        var rotations: [String: simd_quatf] = [:]
        var rootOffset = SIMD3<Float>.zero
    }

    private let modelRoot: SCNNode
    private let restRootPosition: SIMD3<Float>
    private var bones: [String: Bone] = [:]
    private var previousPose = Pose()
    private var elapsed: TimeInterval = 0
    private var transitionElapsed: TimeInterval = 1
    private var transitionDuration: TimeInterval = 1
    private var petElapsed: TimeInterval = .infinity
    private var facingYaw: Float = 0
    private(set) var state: PetBehaviorState = .observing

    private static let requiredBones: Set<String> = [
        "pelvis", "spine1", "spine2", "neck", "head",
        "tail1", "tail2", "tail3",
        "frontLeftUpper", "frontLeftLower", "frontLeftPaw",
        "frontRightUpper", "frontRightLower", "frontRightPaw",
        "hindLeftUpper", "hindLeftLower", "hindLeftPaw",
        "hindRightUpper", "hindRightLower", "hindRightPaw",
    ]

    init?(modelRoot: SCNNode, boneNames: [String: String]) {
        self.modelRoot = modelRoot
        restRootPosition = modelRoot.simdPosition
        for (semanticName, nodeName) in boneNames {
            guard let node = modelRoot.childNode(withName: nodeName, recursively: true) else {
                continue
            }
            bones[semanticName] = Bone(node: node, restOrientation: node.simdOrientation)
        }
        guard Self.requiredBones.isSubset(of: Set(bones.keys)) else { return nil }
    }

    func requestState(_ next: PetBehaviorState, transitionDuration: TimeInterval) {
        previousPose = captureCurrentPose()
        state = next
        self.transitionDuration = max(transitionDuration, 0.001)
        transitionElapsed = transitionDuration == 0 ? self.transitionDuration : 0
    }

    func requestPet() {
        petElapsed = 0
    }

    func setFacingYaw(_ yaw: Float) {
        facingYaw = yaw
    }

    func update(deltaTime: TimeInterval) {
        let dt = min(max(deltaTime, 0), 0.1)
        elapsed += dt
        transitionElapsed = min(transitionDuration, transitionElapsed + dt)
        petElapsed += dt
        var target = pose(for: state, time: elapsed)
        applyPetResponse(to: &target)
        let rawProgress = Float(transitionElapsed / transitionDuration)
        let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
        apply(blend(from: previousPose, to: target, progress: progress))
        modelRoot.simdEulerAngles.y = facingYaw
    }

    private func captureCurrentPose() -> Pose {
        var pose = Pose(rootOffset: modelRoot.simdPosition - restRootPosition)
        for (name, bone) in bones {
            pose.rotations[name] = simd_normalize(bone.restOrientation.inverse * bone.node.simdOrientation)
        }
        return pose
    }

    private func pose(for state: PetBehaviorState, time: TimeInterval) -> Pose {
        switch state {
        case .walking: walkingPose(time: time)
        case .observing: observingPose(time: time)
        case .loafing: loafPose(time: time)
        case .sleeping: sleepPose(time: time)
        }
    }

    private func observingPose(time: TimeInterval) -> Pose {
        var pose = Pose()
        let breath = sin(Float(time) * 2 * .pi / 4.8)
        let glance = sin(Float(time) * 2 * .pi / 11.0)
        pose.rotations["spine2"] = rotation(0.018 * breath, axis: .x)
        pose.rotations["neck"] = rotation(-0.018 * breath, axis: .x)
        pose.rotations["head"] = rotation(0.075 * glance, axis: .y)
        pose.rotations["earLeft"] = rotation(0.035 * sin(Float(time) * 1.7), axis: .z)
        pose.rotations["earRight"] = rotation(-0.03 * sin(Float(time) * 1.37 + 1.1), axis: .z)
        pose.rotations["tail1"] = rotation(0.09 * sin(Float(time) * 0.72), axis: .y)
        pose.rotations["tail2"] = rotation(0.13 * sin(Float(time) * 0.72 - 0.35), axis: .y)
        pose.rotations["tail3"] = rotation(0.16 * sin(Float(time) * 0.72 - 0.75), axis: .y)
        pose.rotations["tail4"] = rotation(0.18 * sin(Float(time) * 0.72 - 1.1), axis: .y)
        return pose
    }

    private func walkingPose(time: TimeInterval) -> Pose {
        var pose = Pose()
        let cycle = Float(time.truncatingRemainder(dividingBy: 1.08) / 1.08)
        configureLeg(&pose, prefix: "hindLeft", phase: cycle, offset: 0)
        configureLeg(&pose, prefix: "frontLeft", phase: cycle, offset: 0.25)
        configureLeg(&pose, prefix: "hindRight", phase: cycle, offset: 0.5)
        configureLeg(&pose, prefix: "frontRight", phase: cycle, offset: 0.75)
        let body = sin(cycle * 4 * .pi)
        pose.rootOffset.y = 0.012 * (1 - cos(cycle * 4 * .pi))
        pose.rotations["pelvis"] = rotation(0.035 * body, axis: .z)
        pose.rotations["spine1"] = rotation(-0.026 * body, axis: .z)
        pose.rotations["spine2"] = rotation(0.018 * body, axis: .z)
        pose.rotations["neck"] = rotation(-0.025 * body, axis: .x)
        pose.rotations["head"] = rotation(0.018 * body, axis: .x)
        let sway = sin(cycle * 2 * .pi)
        pose.rotations["tail1"] = rotation(-0.16 * sway, axis: .y)
        pose.rotations["tail2"] = rotation(-0.22 * sin(cycle * 2 * .pi - 0.35), axis: .y)
        pose.rotations["tail3"] = rotation(-0.27 * sin(cycle * 2 * .pi - 0.7), axis: .y)
        pose.rotations["tail4"] = rotation(-0.30 * sin(cycle * 2 * .pi - 1.0), axis: .y)
        return pose
    }

    private func loafPose(time: TimeInterval) -> Pose {
        var pose = Pose()
        let breath = sin(Float(time) * 2 * .pi / 5.2)
        pose.rootOffset.y = -0.16
        pose.rotations["pelvis"] = rotation(0.16, axis: .x)
        pose.rotations["spine1"] = rotation(-0.08, axis: .x)
        pose.rotations["spine2"] = rotation(0.025 * breath, axis: .x)
        pose.rotations["neck"] = rotation(0.05 - 0.02 * breath, axis: .x)
        foldLegs(&pose, amount: 0.92)
        pose.rotations["tail1"] = rotation(0.52, axis: .y)
        pose.rotations["tail2"] = rotation(0.68, axis: .y)
        pose.rotations["tail3"] = rotation(0.52, axis: .y)
        return pose
    }

    private func sleepPose(time: TimeInterval) -> Pose {
        var pose = loafPose(time: time)
        let breath = sin(Float(time) * 2 * .pi / 5.8)
        pose.rootOffset.y = -0.21
        pose.rotations["pelvis"] = rotation(0.34, axis: .z) * rotation(0.18, axis: .x)
        pose.rotations["spine1"] = rotation(0.27, axis: .z)
        pose.rotations["spine2"] = rotation(0.18 + 0.016 * breath, axis: .z)
        pose.rotations["neck"] = rotation(0.42, axis: .z) * rotation(0.14, axis: .x)
        pose.rotations["head"] = rotation(0.38, axis: .z) * rotation(-0.16, axis: .x)
        foldLegs(&pose, amount: 1.0)
        pose.rotations["tail1"] = rotation(0.85, axis: .y)
        pose.rotations["tail2"] = rotation(0.92, axis: .y)
        pose.rotations["tail3"] = rotation(0.80, axis: .y)
        pose.rotations["tail4"] = rotation(0.52, axis: .y)
        return pose
    }

    private func configureLeg(
        _ pose: inout Pose,
        prefix: String,
        phase: Float,
        offset: Float
    ) {
        let local = (phase - offset).truncatingRemainder(dividingBy: 1) + (phase < offset ? 1 : 0)
        let stride = sin(local * 2 * .pi)
        let swing = max(0, -sin(local * 2 * .pi))
        let isFront = prefix.hasPrefix("front")
        let direction: Float = isFront ? 1 : -1
        pose.rotations["\(prefix)Upper"] = rotation(direction * 0.34 * stride, axis: .x)
        pose.rotations["\(prefix)Lower"] = rotation(direction * (0.12 + 0.42 * swing), axis: .x)
        pose.rotations["\(prefix)Paw"] = rotation(-direction * 0.24 * swing, axis: .x)
    }

    private func foldLegs(_ pose: inout Pose, amount: Float) {
        for prefix in ["frontLeft", "frontRight"] {
            pose.rotations["\(prefix)Upper"] = rotation(-0.48 * amount, axis: .x)
            pose.rotations["\(prefix)Lower"] = rotation(0.92 * amount, axis: .x)
            pose.rotations["\(prefix)Paw"] = rotation(-0.42 * amount, axis: .x)
        }
        for prefix in ["hindLeft", "hindRight"] {
            pose.rotations["\(prefix)Upper"] = rotation(0.62 * amount, axis: .x)
            pose.rotations["\(prefix)Lower"] = rotation(-1.02 * amount, axis: .x)
            pose.rotations["\(prefix)Paw"] = rotation(0.48 * amount, axis: .x)
        }
    }

    private func applyPetResponse(to pose: inout Pose) {
        guard petElapsed < 1.2 else { return }
        let progress = Float(petElapsed / 1.2)
        let envelope = sin(progress * .pi)
        pose.rotations["head"] = (pose.rotations["head"] ?? simd_quatf())
            * rotation(-0.18 * envelope, axis: .x)
            * rotation(0.12 * envelope, axis: .z)
        pose.rotations["neck"] = (pose.rotations["neck"] ?? simd_quatf())
            * rotation(0.08 * envelope, axis: .z)
        pose.rotations["earLeft"] = rotation(-0.11 * envelope, axis: .z)
        pose.rotations["earRight"] = rotation(0.09 * envelope, axis: .z)
    }

    private func blend(from: Pose, to: Pose, progress: Float) -> Pose {
        var pose = Pose(rootOffset: simd_mix(from.rootOffset, to.rootOffset, SIMD3<Float>(repeating: progress)))
        for name in bones.keys {
            let source = from.rotations[name] ?? simd_quatf()
            let target = to.rotations[name] ?? simd_quatf()
            pose.rotations[name] = simd_slerp(source, target, progress)
        }
        return pose
    }

    private func apply(_ pose: Pose) {
        modelRoot.simdPosition = restRootPosition + pose.rootOffset
        for (name, bone) in bones {
            bone.node.simdOrientation = simd_normalize(
                bone.restOrientation * (pose.rotations[name] ?? simd_quatf())
            )
        }
    }

    private func rotation(_ angle: Float, axis: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: angle, axis: axis)
    }
}

private extension SIMD3<Float> {
    static let x = SIMD3<Float>(1, 0, 0)
    static let y = SIMD3<Float>(0, 1, 0)
    static let z = SIMD3<Float>(0, 0, 1)
}

private extension Array where Element == Float {
    var vector3: SIMD3<Float> {
        SIMD3<Float>(
            indices.contains(0) ? self[0] : 0,
            indices.contains(1) ? self[1] : 0,
            indices.contains(2) ? self[2] : 0
        )
    }

    var scnVector3: SCNVector3 {
        let value = vector3
        return SCNVector3(value.x, value.y, value.z)
    }
}
