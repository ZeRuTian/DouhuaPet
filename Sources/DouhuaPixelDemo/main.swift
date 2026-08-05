import AppKit
import CoreGraphics
import SpriteKit

private enum PixelMotion: Hashable {
    case idle
    case walk
    case run
    case jump
    case dialogue
    case tiredDown
    case rest
    case restReaction
    case windowSettle
    case windowPerch
    case windowTap
}

private enum PetBehavior {
    case idle
    case walk
    case run
    case jump
    case dialogue
    case tiredRest
    case restReaction
    case windowHop
    case windowPerch
    case windowTap
    case windowDismount
    case windowWalk
    case windowRun
}

@MainActor
private protocol PixelSceneDelegate: AnyObject {
    func pixelSceneWasPetted()
    func pixelSceneDragBegan(at screenPoint: CGPoint)
    func pixelSceneDragged(to screenPoint: CGPoint)
    func pixelSceneDragEnded()
}

@MainActor
private final class PixelDemoScene: SKScene {
    weak var interactionDelegate: PixelSceneDelegate?

    private let spriteRoot = SKNode()
    private let sprite = SKSpriteNode()
    private var clips: [PixelMotion: [SKTexture]] = [:]
    private var lastUpdateTime: TimeInterval?
    private var animationTime: TimeInterval = 0
    private var currentMotion: PixelMotion = .idle
    private var idleCycleStartedAt: TimeInterval = 0
    private var dragStart = CGPoint.zero
    private var mouseDownScreenPoint = CGPoint.zero
    private var dragging = false

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill

        clips = Self.loadClips()
        guard clips.values.allSatisfy({ !$0.isEmpty }), clips.count == 11 else {
            let label = SKLabelNode(text: "豆花")
            label.fontName = "PingFangSC-Semibold"
            label.fontSize = 14
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            addChild(label)
            return
        }

        spriteRoot.position = CGPoint(x: size.width * 0.5, y: 0)
        addChild(spriteRoot)

        sprite.texture = clips[.idle]?[0]
        sprite.size = size
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = .zero
        sprite.blendMode = .alpha
        spriteRoot.addChild(sprite)
    }

    required init?(coder: NSCoder) { nil }

    override func didChangeSize(_ oldSize: CGSize) {
        spriteRoot.position = CGPoint(x: size.width * 0.5, y: 0)
        sprite.size = size
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let lastUpdateTime else { return }
        let deltaTime = min(max(currentTime - lastUpdateTime, 0), 0.1)
        animationTime += deltaTime

        if currentMotion == .idle { updateIdle() }
    }

    func setIdle() {
        currentMotion = .idle
        sprite.yScale = 1
        idleCycleStartedAt = animationTime
        applyTexture(clips[.idle]?[0])
    }

    /// Locomotion is distance-driven. `phase` advances only when the panel
    /// actually moves, so paws cannot cycle faster or slower than ground speed.
    func setLocomotion(_ motion: PixelMotion, phase: CGFloat) {
        guard motion == .walk || motion == .run, let frames = clips[motion] else { return }
        currentMotion = motion
        sprite.yScale = 1
        let wrapped = phase - floor(phase)
        let index = min(frames.count - 1, Int(floor(wrapped * CGFloat(frames.count))))
        applyTexture(frames[index])
    }

    func setAction(_ motion: PixelMotion, progress: CGFloat) {
        guard motion == .jump || motion == .dialogue, let frames = clips[motion] else { return }
        currentMotion = motion
        sprite.yScale = 1
        let clamped = min(max(progress, 0), 1)
        let index: Int
        if motion == .jump {
            // The jump uses a dedicated eight-pose clip. Advancing evenly
            // avoids the long silhouette holds that made the old four-pose
            // jump read as a succession of different cats.
            index = min(
                frames.count - 1,
                Int(floor(clamped * CGFloat(frames.count)))
            )
        } else {
            if clamped < 0.16 { index = 0 }
            else if clamped < 0.34 { index = 1 }
            else if clamped < 0.56 { index = 2 }
            else { index = 3 }
        }
        applyTexture(frames[index])
    }

    func setTiredDown(progress: CGFloat) {
        setProgressiveClip(.tiredDown, progress: progress)
    }

    func setRestLoop(elapsed: TimeInterval) {
        guard let frames = clips[.rest], frames.count == 8 else { return }
        currentMotion = .rest
        sprite.yScale = 1
        let durations: [TimeInterval] = [1.3, 0.8, 0.8, 0.7, 0.55, 0.5, 0.75, 1.0]
        var localTime = elapsed.truncatingRemainder(dividingBy: durations.reduce(0, +))
        for (index, duration) in durations.enumerated() {
            if localTime < duration {
                applyTexture(frames[index])
                return
            }
            localTime -= duration
        }
        applyTexture(frames[0])
    }

    func setRestReaction(progress: CGFloat) {
        setProgressiveClip(.restReaction, progress: progress)
    }

    func setWindowSettle(progress: CGFloat) {
        setProgressiveClip(.windowSettle, progress: progress)
    }

    func setWindowPerchLoop(elapsed: TimeInterval) {
        guard let frames = clips[.windowPerch], frames.count == 8 else { return }
        currentMotion = .windowPerch
        sprite.yScale = 1
        let durations: [TimeInterval] = [1.15, 0.72, 0.62, 0.44, 0.34, 0.58, 0.76, 1.05]
        var localTime = elapsed.truncatingRemainder(dividingBy: durations.reduce(0, +))
        for (index, duration) in durations.enumerated() {
            if localTime < duration {
                applyTexture(frames[index])
                return
            }
            localTime -= duration
        }
        applyTexture(frames[0])
    }

    func setWindowTap(progress: CGFloat) {
        setProgressiveClip(.windowTap, progress: progress)
    }

    func setFacing(direction: CGFloat) {
        spriteRoot.xScale = direction >= 0 ? 1 : -1
    }

    func containsCat(_ point: CGPoint) -> Bool {
        let activeRegion = CGRect(
            x: size.width * 0.025,
            y: size.height * 0.06,
            width: size.width * 0.95,
            height: size.height * 0.82
        )
        return activeRegion.contains(point)
    }

    func playPetResponse() {
        showHeart()
    }

    private func updateIdle() {
        guard let frames = clips[.idle], frames.count == 8 else { return }
        let durations: [TimeInterval] = [1.4, 0.7, 0.7, 0.7, 1.8, 0.28, 0.22, 0.45]
        let cycleDuration = durations.reduce(0, +)
        var localTime = (animationTime - idleCycleStartedAt)
            .truncatingRemainder(dividingBy: cycleDuration)
        for (index, duration) in durations.enumerated() {
            if localTime < duration {
                applyTexture(frames[index])
                return
            }
            localTime -= duration
        }
        applyTexture(frames[0])
    }

    private func setProgressiveClip(_ motion: PixelMotion, progress: CGFloat) {
        guard let frames = clips[motion], !frames.isEmpty else { return }
        currentMotion = motion
        sprite.yScale = 1
        let clamped = min(max(progress, 0), 1)
        let index = min(
            frames.count - 1,
            Int(floor(clamped * CGFloat(frames.count)))
        )
        applyTexture(frames[index])
    }

    private func applyTexture(_ texture: SKTexture?) {
        guard let texture, sprite.texture !== texture else { return }
        sprite.texture = texture
    }

    private func showHeart() {
        let heart = SKLabelNode(text: "♥")
        heart.fontName = "Menlo-Bold"
        heart.fontColor = NSColor(calibratedRed: 0.92, green: 0.30, blue: 0.34, alpha: 1)
        heart.fontSize = 7
        heart.position = CGPoint(x: size.width * 0.62, y: size.height * 0.76)
        heart.zPosition = 10
        addChild(heart)
        let rise = SKAction.moveBy(x: 0, y: 6, duration: 0.75)
        rise.timingMode = .easeOut
        heart.run(.sequence([.group([rise, .fadeOut(withDuration: 0.75)]), .removeFromParent()]))
    }

    private static func loadClips() -> [PixelMotion: [SKTexture]] {
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app",
           let resources = Bundle.main.resourceURL,
           let appBundle = Bundle(
               url: resources.appendingPathComponent(
                   "DouhuaPet_DouhuaPixelDemo.bundle",
                   isDirectory: true
               )
           ) {
            bundle = appBundle
        } else {
            bundle = Bundle.module
        }

        let idle = loadTextures(
            prefix: "douhua_pixel_v9_idle",
            indices: Array(0..<8),
            bundle: bundle
        )
        let walk = loadTextures(
            prefix: "douhua_pixel_v9_walk",
            indices: Array(0..<8),
            bundle: bundle
        )
        let run = loadTextures(
            prefix: "douhua_pixel_v9_run",
            indices: Array(0..<8),
            bundle: bundle
        )
        let jump = loadTextures(
            prefix: "douhua_pixel_v9_jump",
            indices: Array(0..<8),
            bundle: bundle
        )
        let actions = loadTextures(
            prefix: "douhua_pixel_v9_action",
            indices: Array(0..<8),
            bundle: bundle
        )
        let tiredDown = loadTextures(
            prefix: "douhua_pixel_v10_tired_down",
            indices: Array(0..<8),
            bundle: bundle
        )
        let rest = loadTextures(
            prefix: "douhua_pixel_v10_rest",
            indices: Array(0..<8),
            bundle: bundle
        )
        let restReaction = loadTextures(
            prefix: "douhua_pixel_v10_rest_reaction",
            indices: Array(0..<8),
            bundle: bundle
        )
        let windowSettle = loadTextures(
            prefix: "douhua_pixel_v11_window_settle",
            indices: Array(0..<8),
            bundle: bundle
        )
        let windowPerch = loadTextures(
            prefix: "douhua_pixel_v11_window_perch",
            indices: Array(0..<8),
            bundle: bundle
        )
        let windowTap = loadTextures(
            prefix: "douhua_pixel_v11_window_tap",
            indices: Array(0..<8),
            bundle: bundle
        )
        return [
            .idle: idle,
            .walk: walk,
            .run: run,
            .jump: jump,
            .dialogue: Array(actions.suffix(4)),
            .tiredDown: tiredDown,
            .rest: rest,
            .restReaction: restReaction,
            .windowSettle: windowSettle,
            .windowPerch: windowPerch,
            .windowTap: windowTap,
        ]
    }

    private static func loadTextures(
        prefix: String,
        indices: [Int],
        bundle: Bundle
    ) -> [SKTexture] {
        indices.compactMap { index in
            let name = String(format: "\(prefix)_%02d", index)
            guard let url = bundle.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { return nil }
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            return texture
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard containsCat(point) else { return }
        dragStart = point
        mouseDownScreenPoint = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard containsCat(dragStart) else { return }
        let point = event.location(in: self)
        if !dragging, hypot(point.x - dragStart.x, point.y - dragStart.y) >= 5 {
            dragging = true
            interactionDelegate?.pixelSceneDragBegan(at: mouseDownScreenPoint)
        }
        if dragging { interactionDelegate?.pixelSceneDragged(to: NSEvent.mouseLocation) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            interactionDelegate?.pixelSceneDragEnded()
        } else if containsCat(dragStart) {
            playPetResponse()
            interactionDelegate?.pixelSceneWasPetted()
        }
        dragging = false
        dragStart = .zero
    }
}

@MainActor
private final class PixelDemoPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

#if false
@MainActor
private final class PixelDemoAppDelegate: NSObject, NSApplicationDelegate, PixelSceneDelegate {
    private let panelSize = CGSize(width: 100, height: 60)
    private var panel: PixelDemoPanel!
    private var scene: PixelDemoScene!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pointerTimer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var phaseRemaining: TimeInterval = 2.8
    private var wantsWalking = false
    private var autoDemo = true
    private var direction: CGFloat = -1
    private var velocity: CGFloat = 0
    private var dragging = false
    private var dragOffset = CGPoint.zero
    private var cachedIgnoresMouse = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeMenu()
        startTimers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        pointerTimer?.invalidate()
    }

    private var screenUnderMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func makePanel() {
        let screen = screenUnderMouse
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - panelSize.width * 0.5,
            y: visible.minY + 28
        )
        panel = PixelDemoPanel(
            contentRect: CGRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = SKView(frame: CGRect(origin: .zero, size: panelSize))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        scene = PixelDemoScene(size: panelSize)
        scene.interactionDelegate = self
        scene.setFacing(direction: direction)
        view.presentScene(scene)
        panel.contentView = view
        panel.orderFrontRegardless()
        locomotionModelX = origin.x
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "豆花·像素"
        statusItem.button?.toolTip = "豆花像素动画 Demo"

        let menu = NSMenu()
        menu.addItem(item("继续自动演示", #selector(enableAutoDemo)))
        menu.addItem(item("立即行走", #selector(startWalkingNow)))
        menu.addItem(item("停下来", #selector(stopWalkingNow)))
        menu.addItem(item("回到屏幕中间", #selector(callHome)))
        menu.addItem(.separator())
        menu.addItem(item("关于像素 Demo", #selector(showAbout)))
        menu.addItem(item("退出", #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(
        _ title: String,
        _ action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func startTimers() {
        let runtime = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(runtime, forMode: .common)
        timer = runtime

        let pointer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
        }
        RunLoop.main.add(pointer, forMode: .common)
        pointerTimer = pointer
    }

    private func tick() {
        guard !dragging, let screen = screenContainingMost(of: panel.frame) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(max(now - lastTick, 0), 0.1)
        lastTick = now

        if autoDemo {
            phaseRemaining -= deltaTime
            if phaseRemaining <= 0 {
                if wantsWalking {
                    requestWalking(false)
                    phaseRemaining = Double.random(in: 5.5...8.0)
                } else {
                    requestWalking(true)
                    phaseRemaining = Double.random(in: 4.0...6.0)
                }
            }
        }

        let targetVelocity: CGFloat = wantsWalking ? direction * 16 : 0
        let acceleration: CGFloat = wantsWalking ? 32 : 42
        velocity = approach(velocity, targetVelocity, by: acceleration * deltaTime)
        if abs(velocity) < 0.5, !wantsWalking {
            velocity = 0
            scene.setWalking(false)
        }

        guard velocity != 0 else { return }
        let visible = screen.visibleFrame
        var nextX = panel.frame.minX + velocity * deltaTime
        let minimumX = visible.minX
        let maximumX = visible.maxX - panelSize.width
        if nextX <= minimumX || nextX >= maximumX {
            nextX = min(max(nextX, minimumX), maximumX)
            direction *= -1
            velocity = 0
            requestWalking(false)
            phaseRemaining = 1.1
            scene.setFacing(direction: direction)
        }
        panel.setFrameOrigin(CGPoint(x: nextX, y: panel.frame.minY))
    }

    private func requestWalking(_ walking: Bool) {
        wantsWalking = walking
        if walking {
            scene.setFacing(direction: direction)
            scene.setWalking(true)
        }
    }

    private func updateMousePassthrough() {
        if dragging {
            setIgnoresMouseEvents(false)
            return
        }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        setIgnoresMouseEvents(!scene.containsCat(local))
    }

    private func setIgnoresMouseEvents(_ ignores: Bool) {
        guard ignores != cachedIgnoresMouse else { return }
        cachedIgnoresMouse = ignores
        panel.ignoresMouseEvents = ignores
    }

    private func jumpToFrontmostWindow() {
        let anchors = visibleWindowAnchors()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let anchor = anchors.first(where: { $0.ownerPID == frontmostPID })
                ?? anchors.first else {
            beginDialogue(message: "没找到可以站的窗口。")
            return
        }
        beginWindowHop(to: anchor)
    }

    private func visibleWindowAnchors() -> [WindowAnchor] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return windows.compactMap(windowAnchor(from:))
    }

    private func windowInfo(windowID: CGWindowID) -> WindowAnchor? {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
            as? [[String: Any]],
              let info = windows.first else { return nil }
        return windowAnchor(from: info)
    }

    private func windowAnchor(from info: [String: Any]) -> WindowAnchor? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
              owner.int32Value != ownPID,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
              (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let x = bounds["X"] as? NSNumber,
              let y = bounds["Y"] as? NSNumber,
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber else { return nil }

        let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
        guard ownerName != "Dock", ownerName != "Window Server" else { return nil }
        let quartzFrame = CGRect(
            x: x.doubleValue,
            y: y.doubleValue,
            width: width.doubleValue,
            height: height.doubleValue
        )
        guard quartzFrame.width >= 260, quartzFrame.height >= 160,
              let frame = appKitWindowFrame(from: quartzFrame),
              frame.intersects(NSScreen.screens.reduce(into: CGRect.null) { result, screen in
                  result = result.union(screen.visibleFrame)
              }) else { return nil }
        return WindowAnchor(
            windowID: CGWindowID(number.uint32Value),
            ownerPID: owner.int32Value,
            frame: frame
        )
    }

    private func appKitWindowFrame(from quartzFrame: CGRect) -> CGRect? {
        let matches: [(screen: NSScreen, displayFrame: CGRect, overlap: CGFloat)] =
            NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else { return nil }
                let displayFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
                return (screen, displayFrame, displayFrame.intersection(quartzFrame).pixelDemoArea)
            }
        guard let match = matches.max(by: { $0.overlap < $1.overlap }), match.overlap > 0 else {
            return nil
        }
        return CGRect(
            x: match.screen.frame.minX + quartzFrame.minX - match.displayFrame.minX,
            y: match.screen.frame.maxY - (quartzFrame.maxY - match.displayFrame.minY),
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    private func refreshTrackedWindow() -> CGRect? {
        guard let windowID = trackedWindowID,
              let anchor = windowInfo(windowID: windowID),
              trackedWindowOwnerPID == anchor.ownerPID else { return nil }
        trackedWindowFrame = anchor.frame
        return anchor.frame
    }

    private func windowPanelOrigin(for frame: CGRect) -> CGPoint {
        let safeLeft = frame.minX + 18
        let safeRight = frame.maxX - 18
        let desiredCenter = frame.minX + frame.width * windowAnchorFraction
        let center = min(max(desiredCenter, safeLeft), safeRight)
        let footBaseline = panelSize.height * (112 / 120)
        return CGPoint(
            x: center - panelSize.width * 0.5,
            y: frame.maxY - footBaseline
        )
    }

    private func clearWindowTracking() {
        trackedWindowID = nil
        trackedWindowOwnerPID = nil
        trackedWindowFrame = nil
    }

    private func snapToWindowAfterDragIfNeeded() -> Bool {
        let footY = panel.frame.minY + panelSize.height * (112 / 120)
        let centerX = panel.frame.midX
        guard let anchor = visibleWindowAnchors()
            .filter({
                centerX >= $0.frame.minX + 8 && centerX <= $0.frame.maxX - 8
                    && abs(footY - $0.frame.maxY) <= 24
            })
            .min(by: { abs(footY - $0.frame.maxY) < abs(footY - $1.frame.maxY) })
        else { return false }

        trackedWindowID = anchor.windowID
        trackedWindowOwnerPID = anchor.ownerPID
        trackedWindowFrame = anchor.frame
        windowAnchorFraction = min(
            max((centerX - anchor.frame.minX) / anchor.frame.width, 0.16),
            0.84
        )
        direction = windowAnchorFraction < 0.5 ? 1 : -1
        behavior = .windowPerch
        windowSettleElapsed = windowSettleDuration
        windowPerchElapsed = 0
        panel.setFrameOrigin(windowPanelOrigin(for: anchor.frame))
        scene.setFacing(direction: direction)
        scene.setWindowPerchLoop(elapsed: 0)
        return true
    }

    private func approach(_ value: CGFloat, _ target: CGFloat, by amount: CGFloat) -> CGFloat {
        if value < target { return min(value + amount, target) }
        if value > target { return max(value - amount, target) }
        return value
    }

    private func screenContainingMost(of frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).pixelDemoArea
                < rhs.visibleFrame.intersection(frame).pixelDemoArea
        }
    }

    func pixelSceneWasPetted() {
        autoDemo = false
        requestWalking(false)
        phaseRemaining = 4
    }

    func pixelSceneDragBegan(at screenPoint: CGPoint) {
        dragging = true
        dragOffset = CGPoint(
            x: screenPoint.x - panel.frame.minX,
            y: screenPoint.y - panel.frame.minY
        )
        requestWalking(false)
    }

    func pixelSceneDragged(to screenPoint: CGPoint) {
        panel.setFrameOrigin(
            CGPoint(x: screenPoint.x - dragOffset.x, y: screenPoint.y - dragOffset.y)
        )
    }

    func pixelSceneDragEnded() {
        dragging = false
        if let screen = screenContainingMost(of: panel.frame) {
            var frame = panel.frame
            frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
            panel.setFrame(frame, display: true)
        }
    }

    @objc private func enableAutoDemo() {
        autoDemo = true
        phaseRemaining = 0.2
    }

    @objc private func startWalkingNow() {
        autoDemo = false
        requestWalking(true)
    }

    @objc private func stopWalkingNow() {
        autoDemo = false
        requestWalking(false)
    }

    @objc private func callHome() {
        let screen = screenUnderMouse
        let origin = CGPoint(
            x: screen.visibleFrame.midX - panelSize.width * 0.5,
            y: screen.visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        velocity = 0
        requestWalking(false)
        autoDemo = true
        phaseRemaining = 2.5
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "豆花像素动画 Demo"
        alert.informativeText = "这是 80×60 完整轮廓修正版：按八个完整猫主体分帧，脸部、前爪不会再被图集格线裁切；近侧与远侧四条腿共同参与四拍步态。点击豆花可显示互动爱心，也可直接拖动。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
#endif

private struct WindowAnchor {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
}

private enum WindowDeparture {
    case ground
    case locomotion(PixelMotion, TimeInterval)
    case window(WindowAnchor)
}

@MainActor
private final class DialogueBubbleView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.frame = bounds.insetBy(dx: 8, dy: 8)
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        label.font = NSFont(name: "PingFangSC-Medium", size: 12)
        label.textColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func setMessage(_ message: String) {
        label.stringValue = message
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bubbleRect = bounds.insetBy(dx: 1, dy: 6).offsetBy(dx: 0, dy: 5)
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
        bubble.fill()
        NSColor(calibratedWhite: 0.22, alpha: 0.72).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()

        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: bounds.midX - 5, y: 6))
        tail.line(to: CGPoint(x: bounds.midX + 5, y: 6))
        tail.line(to: CGPoint(x: bounds.midX, y: 1))
        tail.close()
        NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
        tail.fill()
    }
}

@MainActor
private final class PixelDemoAppDelegate: NSObject, NSApplicationDelegate, PixelSceneDelegate {
    // A wider transparent canvas lets fully extended run/jump poses retain the
    // exact idle character scale. Visible cat size remains unchanged.
    private let panelSize = CGSize(width: 100, height: 60)
    private let bubbleSize = CGSize(width: 132, height: 42)
    private let walkSpeed: CGFloat = 16
    private let runSpeed: CGFloat = 42
    private let walkStride: CGFloat = 28
    private let runStride: CGFloat = 40
    private let windowWalkSpeed: CGFloat = 12
    private let windowRunSpeed: CGFloat = 32

    private var panel: PixelDemoPanel!
    private var dialoguePanel: PixelDemoPanel!
    private var dialogueView: DialogueBubbleView!
    private var scene: PixelDemoScene!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pointerTimer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    private var behavior: PetBehavior = .idle
    private var behaviorRemaining: TimeInterval = 7
    private var autoDemo = true
    private var direction: CGFloat = -1
    private var velocity: CGFloat = 0
    private var locomotionModelX: CGFloat = 0
    private var gaitPhase: CGFloat = 0
    private var pendingTransition: PetBehavior?
    private var walkMayEscalate = true

    private var jumpElapsed: TimeInterval = 0
    private let jumpDuration: TimeInterval = 0.78
    private var jumpStartOrigin = CGPoint.zero
    private var dialogueElapsed: TimeInterval = 0
    private let dialogueDuration: TimeInterval = 3.2
    private var bubbleShown = false

    private var stamina: CGFloat = 1
    private var tiredRestElapsed: TimeInterval = 0
    private var tiredRestDuration: TimeInterval = 0
    private let tiredDownDuration: TimeInterval = 1.45
    private var restReactionElapsed: TimeInterval = 0
    private let restReactionDuration: TimeInterval = 1.85
    private var restResumeRemaining: TimeInterval = 0

    private var trackedWindowID: CGWindowID?
    private var trackedWindowOwnerPID: pid_t?
    private var trackedWindowFrame: CGRect?
    private var windowAnchorFraction: CGFloat = 0.34
    private var windowHopElapsed: TimeInterval = 0
    private var windowHopDuration: TimeInterval = 0.92
    private var windowHopStartOrigin = CGPoint.zero
    private var windowHopTargetOrigin = CGPoint.zero
    private var windowHopArrivesOnWindow = true
    private var windowSettleElapsed: TimeInterval = 0
    private let windowSettleDuration: TimeInterval = 1.28
    private var windowPerchElapsed: TimeInterval = 0
    private var windowActivityRemaining: TimeInterval = 16
    private var windowTapElapsed: TimeInterval = 0
    private let windowTapDuration: TimeInterval = 1.55
    private var windowLocomotionRemaining: TimeInterval = 0
    private var windowLocomotionStopping = false
    private var windowDeparture: WindowDeparture = .ground
    private var launchWindowMotion: PixelMotion?

    private var dragging = false
    private var dragOffset = CGPoint.zero
    private var cachedIgnoresMouse = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeDialoguePanel()
        makeMenu()
        beginLaunchBehavior()
        startTimers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        pointerTimer?.invalidate()
    }

    private var screenUnderMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func beginLaunchBehavior() {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--action=") }) else {
            beginIdle(duration: Double.random(in: 8...14))
            return
        }
        autoDemo = false
        switch argument.replacingOccurrences(of: "--action=", with: "") {
        case "walk":
            beginWalk(duration: .infinity, canEscalate: false)
        case "run":
            beginRun(duration: .infinity)
        case "jump":
            beginJump()
        case "dialogue":
            beginDialogue(message: "嗯？")
        case "rest":
            beginTiredRest(duration: 12)
        case "rest-reaction":
            beginTiredRest(duration: 12)
            tiredRestElapsed = tiredDownDuration
            beginRestReaction()
        case "window":
            jumpToFrontmostWindow()
        case "window-walk":
            launchWindowMotion = .walk
            jumpToFrontmostWindow()
        case "window-run":
            launchWindowMotion = .run
            jumpToFrontmostWindow()
        default:
            beginIdle(duration: 60)
        }
    }

    private func makePanel() {
        let screen = screenUnderMouse
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - panelSize.width * 0.5,
            y: visible.minY + 28
        )
        panel = PixelDemoPanel(
            contentRect: CGRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = SKView(frame: CGRect(origin: .zero, size: panelSize))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        scene = PixelDemoScene(size: panelSize)
        scene.interactionDelegate = self
        scene.setFacing(direction: direction)
        view.presentScene(scene)
        panel.contentView = view
        panel.orderFrontRegardless()
        locomotionModelX = origin.x
    }

    private func makeDialoguePanel() {
        dialoguePanel = PixelDemoPanel(
            contentRect: CGRect(origin: .zero, size: bubbleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dialoguePanel.isReleasedWhenClosed = false
        dialoguePanel.isOpaque = false
        dialoguePanel.backgroundColor = .clear
        dialoguePanel.level = .floating
        dialoguePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        dialoguePanel.hidesOnDeactivate = false
        dialoguePanel.hasShadow = true
        dialoguePanel.ignoresMouseEvents = true
        dialogueView = DialogueBubbleView(frame: CGRect(origin: .zero, size: bubbleSize))
        dialoguePanel.contentView = dialogueView
        dialoguePanel.alphaValue = 0
        positionDialogueBubble()
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "豆花·像素"
        statusItem.button?.toolTip = "豆花像素动画 Demo"

        let menu = NSMenu()
        menu.addItem(item("继续自动演示", #selector(enableAutoDemo)))
        menu.addItem(.separator())
        menu.addItem(item("慢慢走", #selector(startWalkingNow)))
        menu.addItem(item("短跑一下", #selector(startRunningNow)))
        menu.addItem(item("跑到累为止", #selector(runUntilTiredNow)))
        menu.addItem(item("趴下休息", #selector(restNow)))
        menu.addItem(item("跳一下", #selector(jumpNow)))
        menu.addItem(item("和豆花说话", #selector(talkNow)))
        menu.addItem(.separator())
        menu.addItem(item("跳到当前窗口", #selector(jumpToWindowNow)))
        menu.addItem(item("从窗口回到地面", #selector(returnToGroundNow)))
        menu.addItem(.separator())
        menu.addItem(item("停下来", #selector(stopMovingNow)))
        menu.addItem(item("回到屏幕中间", #selector(callHome)))
        menu.addItem(.separator())
        menu.addItem(item("关于像素 Demo", #selector(showAbout)))
        menu.addItem(item("退出", #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(
        _ title: String,
        _ action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func startTimers() {
        let runtime = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(runtime, forMode: .common)
        timer = runtime

        let pointer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
        }
        RunLoop.main.add(pointer, forMode: .common)
        pointerTimer = pointer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(max(now - lastTick, 0), 0.1)
        lastTick = now
        guard !dragging, let screen = screenContainingMost(of: panel.frame) else { return }

        switch behavior {
        case .idle:
            updateIdle(deltaTime)
        case .walk:
            updateLocomotion(.walk, deltaTime: deltaTime, screen: screen)
        case .run:
            updateLocomotion(.run, deltaTime: deltaTime, screen: screen)
        case .jump:
            updateJump(deltaTime, screen: screen)
        case .dialogue:
            updateDialogue(deltaTime)
        case .tiredRest:
            updateTiredRest(deltaTime)
        case .restReaction:
            updateRestReaction(deltaTime)
        case .windowHop:
            updateWindowHop(deltaTime)
        case .windowPerch:
            updateWindowPerch(deltaTime)
        case .windowTap:
            updateWindowTap(deltaTime)
        case .windowDismount:
            updateWindowDismount(deltaTime)
        case .windowWalk:
            updateWindowLocomotion(.walk, deltaTime: deltaTime)
        case .windowRun:
            updateWindowLocomotion(.run, deltaTime: deltaTime)
        }
    }

    private func updateIdle(_ deltaTime: TimeInterval) {
        stamina = min(1, stamina + CGFloat(deltaTime) * 0.018)
        guard autoDemo else { return }
        behaviorRemaining -= deltaTime
        guard behaviorRemaining <= 0 else { return }

        let choice = Double.random(in: 0..<1)
        if choice < 0.48 {
            beginWalk(duration: Double.random(in: 4.0...7.0), canEscalate: true)
        } else if choice < 0.55 {
            beginRun(duration: Double.random(in: 0.85...1.2))
        } else if choice < 0.63 {
            beginJump()
        } else if choice < 0.71, let anchor = randomWindowDestination() {
            beginWindowHop(to: anchor)
        } else if choice < 0.82 {
            beginDialogue()
        } else {
            beginIdle(duration: quietInterval())
        }
    }

    private func updateLocomotion(
        _ motion: PixelMotion,
        deltaTime: TimeInterval,
        screen: NSScreen
    ) {
        if motion == .run {
            stamina = max(0, stamina - CGFloat(deltaTime) * 0.32)
            if stamina <= 0.2, pendingTransition == nil {
                pendingTransition = .tiredRest
            }
        } else {
            stamina = max(0, stamina - CGFloat(deltaTime) * 0.008)
        }

        let baseSpeed = motion == .walk ? walkSpeed : runSpeed
        let stride = motion == .walk ? walkStride : runStride
        let acceleration: CGFloat = motion == .walk ? 22 : 84
        let targetSpeed: CGFloat
        switch pendingTransition {
        case .idle:
            targetSpeed = min(baseSpeed, 12)
        case .walk, .run:
            targetSpeed = walkSpeed
        case .tiredRest:
            targetSpeed = min(baseSpeed, 10)
        case .jump, .dialogue, .restReaction,
             .windowHop, .windowPerch, .windowTap, .windowDismount,
             .windowWalk, .windowRun, nil:
            targetSpeed = baseSpeed
        }
        velocity = approach(
            velocity,
            direction * targetSpeed,
            by: acceleration * CGFloat(deltaTime)
        )

        let movement = moveHorizontally(by: velocity * CGFloat(deltaTime), screen: screen)
        gaitPhase = (gaitPhase + movement.distance / stride).truncatingRemainder(dividingBy: 1)
        scene.setLocomotion(motion, phase: gaitPhase)

        if movement.hitBoundary {
            direction *= -1
            velocity = 0
            scene.setFacing(direction: direction)
            if autoDemo {
                if isPlanted(gaitPhase) {
                    beginIdle(duration: quietInterval())
                } else {
                    pendingTransition = .idle
                }
            }
            return
        }

        let canTransition = pendingTransition == .tiredRest
            ? isRestEntryPhase(gaitPhase)
            : isPlanted(gaitPhase)
        if let pendingTransition, canTransition {
            switch pendingTransition {
            case .idle:
                beginIdle(duration: autoDemo ? quietInterval() : 60)
            case .walk:
                beginWalk(duration: Double.random(in: 0.8...1.25), canEscalate: false)
            case .run:
                beginRun(duration: Double.random(in: 0.9...1.5))
            case .jump:
                beginJump()
            case .dialogue:
                beginDialogue()
            case .tiredRest:
                beginTiredRest(duration: Double.random(in: 10...14))
            case .restReaction:
                beginRestReaction()
            case .windowHop, .windowPerch, .windowTap, .windowDismount,
                 .windowWalk, .windowRun:
                beginIdle(duration: 60)
            }
            return
        }

        guard pendingTransition == nil else { return }
        if !autoDemo {
            guard motion == .run, behaviorRemaining.isFinite else { return }
            behaviorRemaining -= deltaTime
            if behaviorRemaining <= 0 { pendingTransition = .idle }
            return
        }
        behaviorRemaining -= deltaTime
        guard behaviorRemaining <= 0 else { return }

        if motion == .run {
            pendingTransition = stamina <= 0.32 ? .tiredRest : .walk
        } else if walkMayEscalate, Double.random(in: 0..<1) < 0.06 {
            pendingTransition = .run
        } else {
            pendingTransition = .idle
        }
    }

    private func updateJump(_ deltaTime: TimeInterval, screen: NSScreen) {
        jumpElapsed += deltaTime
        let progress = min(max(jumpElapsed / jumpDuration, 0), 1)
        let p = CGFloat(progress)
        let smooth = p * p * (3 - 2 * p)
        let visible = screen.visibleFrame
        let nextX = min(
            max(jumpStartOrigin.x + direction * 28 * smooth, visible.minX),
            visible.maxX - panelSize.width
        )
        let nextY = jumpStartOrigin.y + 4 * 26 * p * (1 - p)
        panel.setFrameOrigin(CGPoint(x: nextX, y: nextY))
        scene.setAction(.jump, progress: p)

        if progress >= 1 {
            panel.setFrameOrigin(CGPoint(x: nextX, y: jumpStartOrigin.y))
            beginIdle(duration: autoDemo ? quietInterval() : 60)
        }
    }

    private func updateDialogue(_ deltaTime: TimeInterval) {
        dialogueElapsed += deltaTime
        let progress = min(max(dialogueElapsed / dialogueDuration, 0), 1)
        scene.setAction(.dialogue, progress: CGFloat(progress))
        if progress >= 0.12, progress < 0.9, !bubbleShown { showDialogueBubble() }
        if progress >= 0.9, bubbleShown { hideDialogueBubble(animated: true) }
        if progress >= 1 {
            beginIdle(duration: autoDemo ? quietInterval() : 60)
        }
    }

    private func updateTiredRest(_ deltaTime: TimeInterval) {
        tiredRestElapsed += deltaTime
        stamina = min(1, stamina + CGFloat(deltaTime) * 0.09)
        let remaining = max(0, tiredRestDuration - tiredRestElapsed)

        if tiredRestElapsed < tiredDownDuration {
            scene.setTiredDown(progress: CGFloat(tiredRestElapsed / tiredDownDuration))
        } else if remaining <= tiredDownDuration {
            scene.setTiredDown(progress: CGFloat(remaining / tiredDownDuration))
        } else {
            scene.setRestLoop(elapsed: tiredRestElapsed - tiredDownDuration)
        }

        if tiredRestElapsed >= tiredRestDuration {
            stamina = max(stamina, 0.78)
            beginIdle(duration: autoDemo ? quietInterval() : 60)
        }
    }

    private func updateRestReaction(_ deltaTime: TimeInterval) {
        restReactionElapsed += deltaTime
        let progress = min(max(restReactionElapsed / restReactionDuration, 0), 1)
        scene.setRestReaction(progress: CGFloat(progress))
        if progress >= 1 {
            resumeTiredRest(remaining: restResumeRemaining)
        }
    }

    private func updateWindowHop(_ deltaTime: TimeInterval) {
        windowHopElapsed += deltaTime
        if windowHopArrivesOnWindow {
            guard let frame = refreshTrackedWindow() else {
                beginGroundHop()
                return
            }
            windowHopTargetOrigin = windowPanelOrigin(for: frame)
        }

        let progress = min(max(windowHopElapsed / windowHopDuration, 0), 1)
        let p = CGFloat(progress)
        let smooth = p * p * (3 - 2 * p)
        let dx = windowHopTargetOrigin.x - windowHopStartOrigin.x
        let dy = windowHopTargetOrigin.y - windowHopStartOrigin.y
        let arcHeight = min(max(30, hypot(dx, dy) * 0.11), 72)
        let origin = CGPoint(
            x: windowHopStartOrigin.x + dx * smooth,
            y: windowHopStartOrigin.y + dy * smooth + 4 * arcHeight * p * (1 - p)
        )
        panel.setFrameOrigin(origin)
        scene.setAction(.jump, progress: p)

        guard progress >= 1 else { return }
        panel.setFrameOrigin(windowHopTargetOrigin)
        if windowHopArrivesOnWindow {
            beginWindowPerch()
        } else {
            clearWindowTracking()
            beginIdle(duration: autoDemo ? quietInterval() : 60)
        }
    }

    private func updateWindowPerch(_ deltaTime: TimeInterval) {
        guard let frame = refreshTrackedWindow() else {
            beginWindowDismount()
            return
        }
        panel.setFrameOrigin(windowPanelOrigin(for: frame))
        windowPerchElapsed += deltaTime
        if windowSettleElapsed < windowSettleDuration {
            windowSettleElapsed += deltaTime
            scene.setWindowSettle(
                progress: CGFloat(min(windowSettleElapsed / windowSettleDuration, 1))
            )
        } else {
            if let launchWindowMotion {
                self.launchWindowMotion = nil
                beginWindowDismount(
                    toward: .locomotion(launchWindowMotion, .infinity)
                )
                return
            }
            scene.setWindowPerchLoop(elapsed: windowPerchElapsed)
            guard autoDemo else { return }
            windowActivityRemaining -= deltaTime
            if windowActivityRemaining <= 0 {
                chooseAutomaticWindowActivity()
            }
        }
    }

    private func updateWindowLocomotion(_ motion: PixelMotion, deltaTime: TimeInterval) {
        guard let frame = refreshTrackedWindow() else {
            windowDeparture = .ground
            beginGroundHop()
            return
        }

        let alignedOrigin = windowPanelOrigin(for: frame)
        let speed = motion == .walk ? windowWalkSpeed : windowRunSpeed
        let stride = motion == .walk ? walkStride : runStride
        let acceleration: CGFloat = motion == .walk ? 18 : 60
        let targetMagnitude = windowLocomotionStopping ? min(speed, 6) : speed
        velocity = approach(
            velocity,
            direction * targetMagnitude,
            by: acceleration * CGFloat(deltaTime)
        )

        let safeLeft = frame.minX + 18
        let safeRight = frame.maxX - 18
        let proposedCenter = alignedOrigin.x + panelSize.width * 0.5
            + velocity * CGFloat(deltaTime)
        let nextCenter = min(max(proposedCenter, safeLeft), safeRight)
        let nextX = nextCenter - panelSize.width * 0.5
        let selfDistance = abs(nextX - alignedOrigin.x)
        let hitBoundary = abs(nextCenter - proposedCenter) > 0.001
        windowAnchorFraction = min(max((nextCenter - frame.minX) / frame.width, 0.02), 0.98)
        panel.setFrameOrigin(CGPoint(x: nextX, y: windowPanelOrigin(for: frame).y))

        gaitPhase = (gaitPhase + selfDistance / stride).truncatingRemainder(dividingBy: 1)
        scene.setLocomotion(motion, phase: gaitPhase)

        if hitBoundary {
            velocity = 0
            direction *= -1
            scene.setFacing(direction: direction)
            if autoDemo { windowLocomotionStopping = true }
        }

        if motion == .run {
            stamina = max(0, stamina - CGFloat(deltaTime) * 0.12)
            if stamina <= 0.24 { windowLocomotionStopping = true }
        }

        if windowLocomotionRemaining.isFinite, !windowLocomotionStopping {
            windowLocomotionRemaining -= deltaTime
            if windowLocomotionRemaining <= 0 { windowLocomotionStopping = true }
        }

        if windowLocomotionStopping, isPlanted(gaitPhase) {
            beginWindowPerch()
        }
    }

    private func updateWindowTap(_ deltaTime: TimeInterval) {
        let windowStillExists: Bool
        if let frame = refreshTrackedWindow() {
            panel.setFrameOrigin(windowPanelOrigin(for: frame))
            windowStillExists = true
        } else {
            // Finish the paw stroke before standing up. Changing pose families
            // halfway through the reach causes a visible limb snap.
            windowStillExists = false
        }
        windowTapElapsed += deltaTime
        let progress = min(max(windowTapElapsed / windowTapDuration, 0), 1)
        scene.setWindowTap(progress: CGFloat(progress))
        if progress >= 1 {
            if windowStillExists {
                behavior = .windowPerch
                windowSettleElapsed = windowSettleDuration
                windowPerchElapsed = 0
                scene.setWindowPerchLoop(elapsed: 0)
            } else {
                beginWindowDismount()
            }
        }
    }

    private func updateWindowDismount(_ deltaTime: TimeInterval) {
        if let frame = refreshTrackedWindow() {
            panel.setFrameOrigin(windowPanelOrigin(for: frame))
        }
        windowSettleElapsed += deltaTime
        let progress = min(max(windowSettleElapsed / windowSettleDuration, 0), 1)
        scene.setWindowSettle(progress: CGFloat(1 - progress))
        guard progress >= 1 else { return }
        let departure = windowDeparture
        windowDeparture = .ground
        switch departure {
        case .ground:
            beginGroundHop()
        case let .locomotion(motion, duration):
            beginWindowLocomotion(motion, duration: duration)
        case let .window(anchor):
            if windowInfo(windowID: anchor.windowID) != nil {
                beginWindowHop(to: anchor)
            } else {
                beginGroundHop()
            }
        }
    }

    private func beginWindowHop(to anchor: WindowAnchor) {
        hideDialogueBubble(animated: false)
        behavior = .windowHop
        pendingTransition = nil
        velocity = 0
        trackedWindowID = anchor.windowID
        trackedWindowOwnerPID = anchor.ownerPID
        trackedWindowFrame = anchor.frame
        windowAnchorFraction = min(
            max((panel.frame.midX - anchor.frame.minX) / anchor.frame.width, 0.16),
            0.84
        )
        direction = windowAnchorFraction < 0.5 ? 1 : -1
        windowHopArrivesOnWindow = true
        windowHopElapsed = 0
        windowHopDuration = min(max(0.76, hypot(
            panel.frame.midX - anchor.frame.midX,
            panel.frame.minY - anchor.frame.maxY
        ) / 620), 1.12)
        windowHopStartOrigin = panel.frame.origin
        windowHopTargetOrigin = windowPanelOrigin(for: anchor.frame)
        scene.setFacing(direction: direction)
        scene.setAction(.jump, progress: 0)
    }

    private func beginWindowPerch() {
        behavior = .windowPerch
        pendingTransition = nil
        velocity = 0
        windowSettleElapsed = 0
        windowPerchElapsed = 0
        windowActivityRemaining = quietInterval()
        windowLocomotionStopping = false
        scene.setFacing(direction: direction)
        scene.setWindowSettle(progress: 0)
    }

    private func beginWindowTap() {
        guard behavior == .windowPerch,
              windowSettleElapsed >= windowSettleDuration else { return }
        behavior = .windowTap
        windowTapElapsed = 0
        scene.setWindowTap(progress: 0)
    }

    private func beginWindowDismount(toward departure: WindowDeparture = .ground) {
        if behavior == .windowDismount {
            windowDeparture = departure
            return
        }
        hideDialogueBubble(animated: false)
        windowDeparture = departure
        if behavior == .windowHop {
            switch departure {
            case .ground:
                beginGroundHop()
            case let .locomotion(motion, duration):
                beginWindowLocomotion(motion, duration: duration)
            case let .window(anchor):
                beginWindowHop(to: anchor)
            }
            return
        }
        if behavior == .windowWalk || behavior == .windowRun {
            switch departure {
            case .ground:
                beginGroundHop()
            case let .locomotion(motion, duration):
                beginWindowLocomotion(motion, duration: duration)
            case let .window(anchor):
                beginWindowHop(to: anchor)
            }
            return
        }
        behavior = .windowDismount
        pendingTransition = nil
        velocity = 0
        windowSettleElapsed = 0
        scene.setWindowSettle(progress: 1)
    }

    private func beginWindowLocomotion(_ motion: PixelMotion, duration: TimeInterval) {
        guard motion == .walk || motion == .run,
              let frame = refreshTrackedWindow() else {
            beginGroundHop()
            return
        }
        hideDialogueBubble(animated: false)
        behavior = motion == .walk ? .windowWalk : .windowRun
        pendingTransition = nil
        velocity = 0
        gaitPhase = 0
        windowLocomotionRemaining = duration
        windowLocomotionStopping = false

        let center = frame.minX + frame.width * windowAnchorFraction
        let leftRoom = center - (frame.minX + 18)
        let rightRoom = frame.maxX - 18 - center
        if direction < 0, leftRoom < 24 {
            direction = 1
        } else if direction > 0, rightRoom < 24 {
            direction = -1
        }
        scene.setFacing(direction: direction)
        scene.setLocomotion(motion, phase: gaitPhase)
    }

    private func beginGroundHop() {
        let screen = screenContainingMost(of: panel.frame) ?? screenUnderMouse
        let visible = screen.visibleFrame
        behavior = .windowHop
        pendingTransition = nil
        velocity = 0
        windowHopArrivesOnWindow = false
        windowHopElapsed = 0
        windowHopDuration = min(max(0.78, abs(panel.frame.minY - visible.minY) / 520), 1.15)
        windowHopStartOrigin = panel.frame.origin
        windowHopTargetOrigin = CGPoint(
            x: min(max(panel.frame.minX, visible.minX), visible.maxX - panelSize.width),
            y: visible.minY + 28
        )
        scene.setAction(.jump, progress: 0)
    }

    private func beginIdle(duration: TimeInterval) {
        clearWindowTracking()
        hideDialogueBubble(animated: false)
        behavior = .idle
        behaviorRemaining = duration
        pendingTransition = nil
        velocity = 0
        scene.setIdle()
    }

    private func beginWalk(duration: TimeInterval, canEscalate: Bool) {
        clearWindowTracking()
        hideDialogueBubble(animated: false)
        locomotionModelX = panel.frame.minX
        ensureGroundDirectionHasRoom()
        if behavior != .run { gaitPhase = 0 }
        behavior = .walk
        behaviorRemaining = duration
        pendingTransition = nil
        walkMayEscalate = canEscalate
        scene.setFacing(direction: direction)
        scene.setLocomotion(.walk, phase: gaitPhase)
    }

    private func beginRun(duration: TimeInterval) {
        clearWindowTracking()
        hideDialogueBubble(animated: false)
        locomotionModelX = panel.frame.minX
        ensureGroundDirectionHasRoom()
        if behavior != .walk, behavior != .run { gaitPhase = 0 }
        behavior = .run
        behaviorRemaining = duration
        pendingTransition = nil
        scene.setFacing(direction: direction)
        scene.setLocomotion(.run, phase: gaitPhase)
    }

    private func beginJump() {
        clearWindowTracking()
        hideDialogueBubble(animated: false)
        stamina = max(0, stamina - 0.08)
        behavior = .jump
        velocity = 0
        jumpElapsed = 0
        jumpStartOrigin = panel.frame.origin
        scene.setFacing(direction: direction)
        scene.setAction(.jump, progress: 0)
    }

    private func beginDialogue(message: String? = nil) {
        clearWindowTracking()
        behavior = .dialogue
        velocity = 0
        dialogueElapsed = 0
        bubbleShown = false
        dialogueView.setMessage(message ?? randomDialogue())
        scene.setFacing(direction: direction)
        scene.setAction(.dialogue, progress: 0)
        positionDialogueBubble()
    }

    private func beginTiredRest(duration: TimeInterval) {
        clearWindowTracking()
        hideDialogueBubble(animated: false)
        behavior = .tiredRest
        velocity = 0
        pendingTransition = nil
        tiredRestElapsed = 0
        tiredRestDuration = max(duration, tiredDownDuration * 2 + 3)
        scene.setFacing(direction: direction)
        scene.setTiredDown(progress: 0)
    }

    private func beginRestReaction() {
        guard behavior == .tiredRest,
              tiredRestElapsed >= tiredDownDuration,
              tiredRestDuration - tiredRestElapsed > tiredDownDuration else { return }
        restResumeRemaining = max(tiredRestDuration - tiredRestElapsed, 4.5)
        behavior = .restReaction
        velocity = 0
        restReactionElapsed = 0
        scene.setRestReaction(progress: 0)
    }

    private func resumeTiredRest(remaining: TimeInterval) {
        behavior = .tiredRest
        velocity = 0
        tiredRestElapsed = tiredDownDuration
        tiredRestDuration = tiredDownDuration + max(remaining, 4.5)
        scene.setRestLoop(elapsed: 0)
    }

    private func moveHorizontally(
        by delta: CGFloat,
        screen: NSScreen
    ) -> (distance: CGFloat, hitBoundary: Bool) {
        let visible = screen.visibleFrame
        let oldX = locomotionModelX
        let proposedX = oldX + delta
        let nextX = min(max(proposedX, visible.minX), visible.maxX - panelSize.width)
        locomotionModelX = nextX
        panel.setFrameOrigin(CGPoint(x: nextX, y: panel.frame.minY))
        return (abs(nextX - oldX), abs(nextX - proposedX) > 0.001)
    }

    private func ensureGroundDirectionHasRoom() {
        let screen = screenContainingMost(of: panel.frame) ?? screenUnderMouse
        let visible = screen.visibleFrame
        locomotionModelX = min(
            max(panel.frame.minX, visible.minX),
            visible.maxX - panelSize.width
        )
        let leftRoom = locomotionModelX - visible.minX
        let rightRoom = visible.maxX - panelSize.width - locomotionModelX
        if direction < 0, leftRoom < 24 {
            direction = 1
        } else if direction > 0, rightRoom < 24 {
            direction = -1
        }
    }

    private func isPlanted(_ phase: CGFloat) -> Bool {
        let wrapped = phase - floor(phase)
        let distances = [abs(wrapped), abs(wrapped - 0.5), abs(wrapped - 1)]
        return distances.min() ?? 1 < 0.035
    }

    private func isRestEntryPhase(_ phase: CGFloat) -> Bool {
        let wrapped = phase - floor(phase)
        return min(abs(wrapped), abs(wrapped - 1)) < 0.035
    }

    private func randomDialogue() -> String {
        ["嗯？", "我在看你。", "先摸一下再说。", "该休息一会儿了。", "今天也要认真。"].randomElement() ?? "嗯？"
    }

    private func quietInterval() -> TimeInterval {
        Double.random(in: 12...22)
    }

    private func chooseAutomaticWindowActivity() {
        let choice = Double.random(in: 0..<1)
        if choice < 0.55 {
            beginWindowDismount(
                toward: .locomotion(.walk, Double.random(in: 4.5...7.5))
            )
        } else if choice < 0.63 {
            beginWindowDismount(
                toward: .locomotion(.run, Double.random(in: 0.75...1.05))
            )
        } else if choice < 0.79,
                  let anchor = randomWindowDestination(excluding: trackedWindowID) {
            beginWindowDismount(toward: .window(anchor))
        } else if choice < 0.87 {
            beginWindowDismount(toward: .ground)
        } else {
            windowActivityRemaining = quietInterval()
        }
    }

    private func showDialogueBubble() {
        bubbleShown = true
        positionDialogueBubble()
        dialoguePanel.alphaValue = 0
        dialoguePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            dialoguePanel.animator().alphaValue = 1
        }
    }

    private func hideDialogueBubble(animated: Bool) {
        guard bubbleShown || dialoguePanel?.isVisible == true else { return }
        bubbleShown = false
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                dialoguePanel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.dialoguePanel.orderOut(nil) }
            })
        } else {
            dialoguePanel.alphaValue = 0
            dialoguePanel.orderOut(nil)
        }
    }

    private func positionDialogueBubble() {
        guard dialoguePanel != nil, panel != nil else { return }
        let screen = screenContainingMost(of: panel.frame) ?? screenUnderMouse
        let visible = screen.visibleFrame
        let desiredX = panel.frame.midX - bubbleSize.width * 0.5 + direction * 10
        let x = min(max(desiredX, visible.minX), visible.maxX - bubbleSize.width)
        let y = min(panel.frame.maxY - 2, visible.maxY - bubbleSize.height)
        dialoguePanel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func requestStop() {
        hideDialogueBubble(animated: true)
        switch behavior {
        case .walk:
            pendingTransition = .idle
        case .run:
            pendingTransition = .idle
        case .idle:
            beginIdle(duration: 60)
        case .jump, .dialogue, .tiredRest, .restReaction:
            beginIdle(duration: 60)
        case .windowWalk, .windowRun:
            windowLocomotionStopping = true
        case .windowHop, .windowPerch, .windowTap, .windowDismount:
            beginWindowDismount()
        }
    }

    private func updateMousePassthrough() {
        if dragging {
            setIgnoresMouseEvents(false)
            return
        }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        setIgnoresMouseEvents(!scene.containsCat(local))
    }

    private func setIgnoresMouseEvents(_ ignores: Bool) {
        guard ignores != cachedIgnoresMouse else { return }
        cachedIgnoresMouse = ignores
        panel.ignoresMouseEvents = ignores
    }

    private func jumpToFrontmostWindow() {
        let anchors = visibleWindowAnchors()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let anchor = anchors.first(where: { $0.ownerPID == frontmostPID })
                ?? anchors.first else {
            beginDialogue(message: "没找到可以站的窗口。")
            return
        }
        beginWindowHop(to: anchor)
    }

    private func visibleWindowAnchors() -> [WindowAnchor] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return windows.compactMap(windowAnchor(from:))
    }

    private func randomWindowDestination(
        excluding excludedWindowID: CGWindowID? = nil
    ) -> WindowAnchor? {
        let candidates = visibleWindowAnchors().filter { anchor in
            guard anchor.windowID != excludedWindowID,
                  let screen = screenContainingMost(of: anchor.frame) else { return false }
            let visible = screen.visibleFrame
            return anchor.frame.width < visible.width * 0.98
                || anchor.frame.height < visible.height * 0.95
        }
        let nearby = candidates.sorted {
            hypot($0.frame.midX - panel.frame.midX, $0.frame.maxY - panel.frame.minY)
                < hypot($1.frame.midX - panel.frame.midX, $1.frame.maxY - panel.frame.minY)
        }
        return Array(nearby.prefix(6)).randomElement()
    }

    private func windowInfo(windowID: CGWindowID) -> WindowAnchor? {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
            as? [[String: Any]],
              let info = windows.first else { return nil }
        return windowAnchor(from: info)
    }

    private func windowAnchor(from info: [String: Any]) -> WindowAnchor? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
              owner.int32Value != ownPID,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
              (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let x = bounds["X"] as? NSNumber,
              let y = bounds["Y"] as? NSNumber,
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber else { return nil }

        let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
        guard ownerName != "Dock", ownerName != "Window Server" else { return nil }
        let quartzFrame = CGRect(
            x: x.doubleValue,
            y: y.doubleValue,
            width: width.doubleValue,
            height: height.doubleValue
        )
        guard quartzFrame.width >= 260, quartzFrame.height >= 160,
              let frame = appKitWindowFrame(from: quartzFrame),
              frame.intersects(NSScreen.screens.reduce(into: CGRect.null) { result, screen in
                  result = result.union(screen.visibleFrame)
              }) else { return nil }
        return WindowAnchor(
            windowID: CGWindowID(number.uint32Value),
            ownerPID: owner.int32Value,
            frame: frame
        )
    }

    private func appKitWindowFrame(from quartzFrame: CGRect) -> CGRect? {
        let matches: [(screen: NSScreen, displayFrame: CGRect, overlap: CGFloat)] =
            NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else { return nil }
                let displayFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
                return (screen, displayFrame, displayFrame.intersection(quartzFrame).pixelDemoArea)
            }
        guard let match = matches.max(by: { $0.overlap < $1.overlap }), match.overlap > 0 else {
            return nil
        }
        return CGRect(
            x: match.screen.frame.minX + quartzFrame.minX - match.displayFrame.minX,
            y: match.screen.frame.maxY - (quartzFrame.maxY - match.displayFrame.minY),
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    private func refreshTrackedWindow() -> CGRect? {
        guard let windowID = trackedWindowID,
              let anchor = windowInfo(windowID: windowID),
              trackedWindowOwnerPID == anchor.ownerPID else { return nil }
        trackedWindowFrame = anchor.frame
        return anchor.frame
    }

    private func windowPanelOrigin(for frame: CGRect) -> CGPoint {
        let safeLeft = frame.minX + 18
        let safeRight = frame.maxX - 18
        let desiredCenter = frame.minX + frame.width * windowAnchorFraction
        let center = min(max(desiredCenter, safeLeft), safeRight)
        let footBaseline = panelSize.height * (112 / 120)
        return CGPoint(
            x: center - panelSize.width * 0.5,
            y: frame.maxY - footBaseline
        )
    }

    private func clearWindowTracking() {
        trackedWindowID = nil
        trackedWindowOwnerPID = nil
        trackedWindowFrame = nil
    }

    private func snapToWindowAfterDragIfNeeded() -> Bool {
        let footY = panel.frame.minY + panelSize.height * (112 / 120)
        let centerX = panel.frame.midX
        guard let anchor = visibleWindowAnchors()
            .filter({
                centerX >= $0.frame.minX + 8 && centerX <= $0.frame.maxX - 8
                    && abs(footY - $0.frame.maxY) <= 24
            })
            .min(by: { abs(footY - $0.frame.maxY) < abs(footY - $1.frame.maxY) })
        else { return false }

        trackedWindowID = anchor.windowID
        trackedWindowOwnerPID = anchor.ownerPID
        trackedWindowFrame = anchor.frame
        windowAnchorFraction = min(
            max((centerX - anchor.frame.minX) / anchor.frame.width, 0.16),
            0.84
        )
        direction = windowAnchorFraction < 0.5 ? 1 : -1
        behavior = .windowPerch
        windowSettleElapsed = windowSettleDuration
        windowPerchElapsed = 0
        windowActivityRemaining = quietInterval()
        panel.setFrameOrigin(windowPanelOrigin(for: anchor.frame))
        scene.setFacing(direction: direction)
        scene.setWindowPerchLoop(elapsed: 0)
        return true
    }

    private func approach(_ value: CGFloat, _ target: CGFloat, by amount: CGFloat) -> CGFloat {
        if value < target { return min(value + amount, target) }
        if value > target { return max(value - amount, target) }
        return value
    }

    private func screenContainingMost(of frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).pixelDemoArea
                < rhs.visibleFrame.intersection(frame).pixelDemoArea
        }
    }

    func pixelSceneWasPetted() {
        autoDemo = false
        if behavior == .windowPerch {
            beginWindowTap()
        } else if behavior == .windowWalk || behavior == .windowRun {
            windowLocomotionStopping = true
        } else if behavior == .tiredRest {
            beginRestReaction()
        } else if behavior != .restReaction,
                  behavior != .windowTap,
                  behavior != .windowHop,
                  behavior != .windowDismount {
            beginDialogue(message: "嗯？")
        }
    }

    func pixelSceneDragBegan(at screenPoint: CGPoint) {
        dragging = true
        dragOffset = CGPoint(
            x: screenPoint.x - panel.frame.minX,
            y: screenPoint.y - panel.frame.minY
        )
        beginIdle(duration: 60)
    }

    func pixelSceneDragged(to screenPoint: CGPoint) {
        panel.setFrameOrigin(
            CGPoint(x: screenPoint.x - dragOffset.x, y: screenPoint.y - dragOffset.y)
        )
    }

    func pixelSceneDragEnded() {
        dragging = false
        if snapToWindowAfterDragIfNeeded() {
            lastTick = ProcessInfo.processInfo.systemUptime
            return
        }
        if let screen = screenContainingMost(of: panel.frame) {
            var frame = panel.frame
            frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
            panel.setFrame(frame, display: true)
        }
        locomotionModelX = panel.frame.minX
        lastTick = ProcessInfo.processInfo.systemUptime
    }

    @objc private func enableAutoDemo() {
        autoDemo = true
        switch behavior {
        case .windowPerch:
            windowActivityRemaining = Double.random(in: 6...10)
        case .windowWalk, .windowRun:
            if !windowLocomotionRemaining.isFinite {
                windowLocomotionRemaining = Double.random(in: 2.5...5)
            }
        case .windowHop, .windowTap, .windowDismount:
            break
        default:
            beginIdle(duration: Double.random(in: 6...10))
        }
    }

    @objc private func startWalkingNow() {
        autoDemo = false
        switch behavior {
        case .windowPerch, .windowTap, .windowDismount:
            beginWindowDismount(toward: .locomotion(.walk, .infinity))
        case .windowWalk, .windowRun:
            beginWindowLocomotion(.walk, duration: .infinity)
        default:
            beginWalk(duration: .infinity, canEscalate: false)
        }
    }

    @objc private func startRunningNow() {
        autoDemo = false
        switch behavior {
        case .windowPerch, .windowTap, .windowDismount:
            beginWindowDismount(toward: .locomotion(.run, 1.25))
        case .windowWalk, .windowRun:
            beginWindowLocomotion(.run, duration: 1.25)
        default:
            beginRun(duration: 1.25)
        }
    }

    @objc private func runUntilTiredNow() {
        autoDemo = false
        switch behavior {
        case .windowPerch, .windowTap, .windowDismount:
            beginWindowDismount(toward: .locomotion(.run, .infinity))
        case .windowWalk, .windowRun:
            beginWindowLocomotion(.run, duration: .infinity)
        default:
            beginRun(duration: .infinity)
        }
    }

    @objc private func restNow() {
        autoDemo = false
        beginTiredRest(duration: 12)
    }

    @objc private func jumpNow() {
        autoDemo = false
        beginJump()
    }

    @objc private func talkNow() {
        autoDemo = false
        beginDialogue()
    }

    @objc private func jumpToWindowNow() {
        autoDemo = false
        jumpToFrontmostWindow()
    }

    @objc private func returnToGroundNow() {
        autoDemo = false
        switch behavior {
        case .windowHop, .windowPerch, .windowTap, .windowDismount,
             .windowWalk, .windowRun:
            beginWindowDismount()
        default:
            beginDialogue(message: "我已经在地面上啦。")
        }
    }

    @objc private func stopMovingNow() {
        autoDemo = false
        requestStop()
    }

    @objc private func callHome() {
        let screen = screenUnderMouse
        let origin = CGPoint(
            x: screen.visibleFrame.midX - panelSize.width * 0.5,
            y: screen.visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
        locomotionModelX = origin.x
        panel.orderFrontRegardless()
        velocity = 0
        autoDemo = true
        beginIdle(duration: Double.random(in: 8...14))
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "豆花像素动画 Demo 0.11"
        alert.informativeText = "豆花现在会以真实位移距离驱动四肢步态：慢走、短跑与窗口顶边行走都不再滑步或原地踏步。自动模式会在较长的安静观察后，低频选择地面慢走、偶尔短跑、跳上窗口、沿窗口慢走或跳到另一个窗口。窗口移动只会整体带着豆花移动，不会让四肢错误加速。应用只读取窗口编号和边界，不读取窗口内容，也不需要录屏或辅助功能权限。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension CGRect {
    var pixelDemoArea: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}

let app = NSApplication.shared
private let delegate = PixelDemoAppDelegate()
app.delegate = delegate
app.run()
withExtendedLifetime(delegate) {}
