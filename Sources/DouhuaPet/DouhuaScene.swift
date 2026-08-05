import AppKit
import AVFoundation
import SpriteKit

@MainActor
protocol DouhuaSceneDelegate: AnyObject {
    func sceneWasPetted()
    func sceneDragBegan(at screenPoint: CGPoint)
    func sceneDragged(to screenPoint: CGPoint)
    func sceneDragEnded()
    func sceneRequestedContextMenu(at screenPoint: CGPoint)
}

/// A single-authority renderer for Douhua's continuous animation.
///
/// The primary contract is one skinned 3D identity driven by a semantic feline
/// skeleton. Until the production USDZ is present, the real 30 FPS alpha video
/// remains the no-regression fallback; PNG sequences are emergency-only.
@MainActor
final class DouhuaScene: SKScene {
    weak var interactionDelegate: DouhuaSceneDelegate?

    private let spriteRoot = SKNode()
    private var rigged3D: Douhua3DController?
    private var liveVideoNode: SKVideoNode?
    private var livePlayer: AVQueuePlayer?
    private var liveLooper: AVPlayerLooper?
    private var sprite: SKSpriteNode?
    private var fallbackLabel: SKLabelNode?
    private var currentMask: SpriteHitMask?
    private var director: PetAnimationDirector?
    private var lastUpdateTime: TimeInterval?
    private var animationFrozen = false

    private(set) var behaviorState: PetBehaviorState = .observing
    private(set) var isFacingRight = false
    private var desiredFacingRight = false

    private var dragActivation = DragActivation(threshold: 4)
    private var delegateDragStarted = false
    private var mouseDownInsidePet = false
    private var mouseDownScreenPoint = CGPoint.zero

    var locomotionIsActive: Bool {
        if rigged3D != nil { return behaviorState == .walking }
        if liveVideoNode != nil { return false }
        return director?.locomotionIsActive ?? (behaviorState == .walking)
    }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(spriteRoot)

        if !buildRigged3D(), !buildLiveVideo(), !buildContinuousSprite(), !buildLegacySprite() {
            buildEmergencyFallback()
        }
        layoutSprite()
        applyCurrentFrame()
    }

    required init?(coder: NSCoder) { nil }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutSprite()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let lastUpdateTime else { return }
        guard !animationFrozen else { return }

        let deltaTime = min(max(currentTime - lastUpdateTime, 0), 0.25)
        rigged3D?.update(deltaTime: deltaTime)
        if director?.update(deltaTime: deltaTime) == true {
            applyCurrentFrame()
        }
        applyFacingIfSafe()
    }

    private func spriteResourceBundle() -> Bundle? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL else { return nil }
            return Bundle(
                url: resources.appendingPathComponent(
                    "DouhuaPet_DouhuaPet.bundle",
                    isDirectory: true
                )
            )
        }
        return Bundle.module
    }

    private func buildContinuousSprite() -> Bool {
        guard let bundle = spriteResourceBundle(),
              let library = PetAnimationLibrary(bundle: bundle) else { return false }
        let director = PetAnimationDirector(library: library)
        let frame = director.currentFrame
        let node = SKSpriteNode(texture: frame.texture)
        node.name = "douhua-continuous-sprite"
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = .zero
        spriteRoot.addChild(node)
        sprite = node
        currentMask = frame.hitMask
        self.director = director
        return true
    }

    private func buildRigged3D() -> Bool {
        guard let bundle = spriteResourceBundle(),
              let controller = Douhua3DController.load(bundle: bundle, viewportSize: size)
        else { return false }
        spriteRoot.addChild(controller.spriteNode)
        rigged3D = controller
        return true
    }

    private func buildLiveVideo() -> Bool {
        guard let bundle = spriteResourceBundle(),
              let url = bundle.url(forResource: "douhua_live_idle", withExtension: "mov")
        else { return false }

        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let node = SKVideoNode(avPlayer: player)
        node.name = "douhua-live-video"
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = .zero
        spriteRoot.addChild(node)

        if let hitURL = bundle.url(forResource: "douhua_live_hit", withExtension: "png"),
           let hitImage = NSImage(contentsOf: hitURL) {
            currentMask = SpriteHitMask(
                image: hitImage,
                maximumDimension: 192,
                alphaThreshold: 18
            )
        }
        liveVideoNode = node
        livePlayer = player
        liveLooper = looper
        player.play()
        return true
    }

    private func buildLegacySprite() -> Bool {
        guard let bundle = spriteResourceBundle(),
              let url = bundle.url(
                  forResource: PetSpriteAsset.observing.rawValue,
                  withExtension: nil
              ),
              let image = NSImage(contentsOf: url),
              let mask = SpriteHitMask(image: image, maximumDimension: 192, alphaThreshold: 18)
        else { return false }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture)
        node.name = "douhua-legacy-fallback-sprite"
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = .zero
        spriteRoot.addChild(node)
        sprite = node
        currentMask = mask
        return true
    }

    private func buildEmergencyFallback() {
        let label = SKLabelNode(text: "🐈")
        label.name = "douhua-emergency-fallback"
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.fontSize = size.height * 0.62
        addChild(label)
        fallbackLabel = label
    }

    private func layoutSprite() {
        spriteRoot.position = CGPoint(x: size.width * 0.5, y: 0)
        rigged3D?.resize(to: size)
        liveVideoNode?.size = size
        sprite?.size = size
        fallbackLabel?.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        fallbackLabel?.fontSize = size.height * 0.62
    }

    func setBehavior(_ state: PetBehaviorState) {
        behaviorState = state
        if let rigged3D {
            rigged3D.requestState(state)
            return
        }
        guard liveVideoNode == nil else { return }
        director?.requestState(state)
        applyCurrentFrame()
    }

    func setFacing(direction: CGFloat) {
        desiredFacingRight = direction > 0
        applyFacingIfSafe()
    }

    func setDragging(_ dragging: Bool) {
        animationFrozen = dragging
        lastUpdateTime = nil
        if dragging {
            rigged3D?.setPaused(true)
            livePlayer?.pause()
        } else {
            rigged3D?.setPaused(false)
            livePlayer?.play()
        }
        let targetY: CGFloat = dragging ? 4 : 0
        let lift = SKAction.moveTo(y: targetY, duration: dragging ? 0.10 : 0.14)
        lift.timingMode = .easeInEaseOut
        spriteRoot.run(lift, withKey: "drag-lift")
    }

    func isPointInsidePet(_ point: CGPoint) -> Bool {
        guard let currentMask else {
            return CatHitRegion(canvasSize: size).contains(point)
        }
        return currentMask.contains(
            point: point,
            canvasSize: size,
            flippedHorizontally: isFacingRight
        )
    }

    private func applyCurrentFrame() {
        guard let director else { return }
        let frame = director.currentFrame
        sprite?.texture = frame.texture
        sprite?.alpha = 1
        currentMask = frame.hitMask
        applyFacingIfSafe()
    }

    private func applyFacingIfSafe() {
        guard desiredFacingRight != isFacingRight else { return }
        if let rigged3D {
            isFacingRight = desiredFacingRight
            rigged3D.setFacingRight(isFacingRight)
            return
        }
        guard liveVideoNode == nil else { return }
        guard director?.canTurnWithoutSliding ?? true else { return }
        isFacingRight = desiredFacingRight
        // Flip only at a planted-paw phase. An animated xScale through zero
        // would visibly squash the cat and is less natural than this clean turn.
        spriteRoot.xScale = isFacingRight ? -1 : 1
    }

    private func playPetResponse() {
        if let rigged3D {
            rigged3D.requestPet()
            return
        }
        guard liveVideoNode == nil else { return }
        director?.requestPet()
        applyCurrentFrame()
    }

    func setPlaybackPaused(_ paused: Bool) {
        rigged3D?.setPaused(paused)
        if paused {
            livePlayer?.pause()
        } else if liveVideoNode != nil {
            livePlayer?.play()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = event.location(in: self)
        mouseDownInsidePet = isPointInsidePet(localPoint)
        guard mouseDownInsidePet else { return }
        dragActivation.begin(at: localPoint)
        delegateDragStarted = false
        mouseDownScreenPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDownInsidePet,
              dragActivation.update(to: event.location(in: self)) else { return }
        if !delegateDragStarted {
            delegateDragStarted = true
            setDragging(true)
            interactionDelegate?.sceneDragBegan(at: mouseDownScreenPoint)
        }
        interactionDelegate?.sceneDragged(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        if delegateDragStarted {
            setDragging(false)
            interactionDelegate?.sceneDragEnded()
        } else if mouseDownInsidePet {
            playPetResponse()
            interactionDelegate?.sceneWasPetted()
        }
        delegateDragStarted = false
        mouseDownInsidePet = false
        dragActivation.end()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isPointInsidePet(event.location(in: self)) else { return }
        interactionDelegate?.sceneRequestedContextMenu(at: NSEvent.mouseLocation)
    }
}
