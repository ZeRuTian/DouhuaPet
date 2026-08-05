import AppKit
import SpriteKit

extension PetSizePreset {
    var panelSize: CGSize {
        switch self {
        case .small: CGSize(width: 200, height: 183)
        case .medium: CGSize(width: 240, height: 220)
        case .large: CGSize(width: 300, height: 275)
        }
    }

    var displayName: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }
}

extension PetActivityPreset {
    var displayName: String {
        switch self {
        case .quiet: "安静"
        case .standard: "标准"
        case .active: "活跃"
        }
    }

    var maximumSpeed: CGFloat {
        switch self {
        case .quiet: 10
        case .standard: 15
        case .active: 21
        }
    }

    var behaviorClockScale: Double {
        switch self {
        case .quiet: 0.78
        case .standard: 1
        case .active: 1.24
        }
    }
}

@MainActor
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, DouhuaSceneDelegate {
    private let settings = PetSettingsStore()

    private var panel: PetPanel!
    private var scene: DouhuaScene!
    private var spriteView: SKView!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var quietItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var sizeItems: [PetSizePreset: NSMenuItem] = [:]
    private var activityItems: [PetActivityPreset: NSMenuItem] = [:]

    private var behavior = PetBehaviorController(state: .observing, duration: 18)
    private var motion: NaturalPatrol!
    private var patrolY: CGFloat = 0
    private var dragOffset = CGPoint.zero
    private var dragging = false
    private var behaviorTimer: Timer?
    private var pointerTimer: Timer?
    private var cachedIgnoresMouseEvents: Bool?
    private var behaviorFramesPerSecond = 8
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastPositionSave = ProcessInfo.processInfo.systemUptime
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []

    private var panelSize: CGSize { settings.size.panelSize }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeMenu()
        registerLifecycleObservers()
        syncMenuState()

        if settings.hidden {
            panel.orderOut(nil)
            panel.ignoresMouseEvents = true
        } else {
            panel.orderFrontRegardless()
            startRuntime()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistPosition()
        stopRuntime(stopPointerTracking: true)
        for (center, token) in notificationTokens {
            center.removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    private var screenUnderMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func makePanel() {
        let screen = restoredScreen() ?? screenUnderMouse
        let origin = restoredOrigin(on: screen)
        patrolY = origin.y

        panel = PetPanel(
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
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        cachedIgnoresMouseEvents = true

        spriteView = SKView(frame: CGRect(origin: .zero, size: panelSize))
        spriteView.autoresizingMask = [.width, .height]
        spriteView.allowsTransparency = true
        // Match SpriteKit composition to the 30 FPS alpha video. The previous
        // 60 Hz scene clock only repeated decoded video frames and used more CPU.
        spriteView.preferredFramesPerSecond = 30
        spriteView.ignoresSiblingOrder = true
        scene = DouhuaScene(size: panelSize)
        scene.interactionDelegate = self
        if settings.quiet {
            behavior = PetBehaviorController(state: .loafing, duration: 120)
        } else if settings.activity == .active {
            behavior = PetBehaviorController(state: .walking, duration: 8)
        }
        scene.setBehavior(behavior.state)
        spriteView.presentScene(scene)
        panel.contentView = spriteView
        panel.sharingType = .readOnly

        motion = makeMotion(position: origin.x, direction: -1)
        scene.setFacing(direction: motion.direction)
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "豆花"
        statusItem.button?.toolTip = "豆花桌面宠物"

        statusMenu = NSMenu()
        statusMenu.addItem(menuItem(title: "叫豆花回来", action: #selector(callHome)))
        quietItem = menuItem(title: "安静模式", action: #selector(toggleQuiet(_:)))
        statusMenu.addItem(quietItem)
        pauseItem = menuItem(title: "暂停", action: #selector(togglePaused))
        statusMenu.addItem(pauseItem)
        visibilityItem = menuItem(title: "隐藏豆花", action: #selector(toggleVisible))
        statusMenu.addItem(visibilityItem)
        statusMenu.addItem(.separator())

        let sizeMenu = NSMenu(title: "体型")
        for preset in PetSizePreset.allCases {
            let item = menuItem(title: preset.displayName, action: #selector(selectSize(_:)))
            item.representedObject = preset.rawValue
            sizeMenu.addItem(item)
            sizeItems[preset] = item
        }
        let sizeRoot = NSMenuItem(title: "体型", action: nil, keyEquivalent: "")
        sizeRoot.submenu = sizeMenu
        statusMenu.addItem(sizeRoot)

        let activityMenu = NSMenu(title: "活跃度")
        for preset in PetActivityPreset.allCases {
            let item = menuItem(title: preset.displayName, action: #selector(selectActivity(_:)))
            item.representedObject = preset.rawValue
            activityMenu.addItem(item)
            activityItems[preset] = item
        }
        let activityRoot = NSMenuItem(title: "活跃度", action: nil, keyEquivalent: "")
        activityRoot.submenu = activityMenu
        statusMenu.addItem(activityRoot)

        statusMenu.addItem(menuItem(title: "重置位置与设置", action: #selector(resetSettings)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem(title: "关于豆花", action: #selector(showAbout)))
        statusMenu.addItem(menuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = statusMenu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func registerLifecycleObservers() {
        let appCenter = NotificationCenter.default
        let screenToken = appCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverAfterEnvironmentChange() }
        }
        notificationTokens.append((appCenter, screenToken))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let sleepToken = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistPosition()
                self?.stopRuntime(stopPointerTracking: true)
            }
        }
        notificationTokens.append((workspaceCenter, sleepToken))

        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverAfterEnvironmentChange()
                if self?.settings.hidden == false { self?.startRuntime() }
            }
        }
        notificationTokens.append((workspaceCenter, wakeToken))
    }

    private func startRuntime() {
        guard !settings.hidden else { return }
        startPointerTracking()
        if settings.paused {
            scene.setPlaybackPaused(true)
            scene.isPaused = true
            spriteView.isPaused = true
            return
        }
        scene.isPaused = false
        spriteView.isPaused = false
        scene.setPlaybackPaused(false)
        scheduleBehaviorTimer()
        tick()
    }

    private func stopRuntime(stopPointerTracking: Bool) {
        behaviorTimer?.invalidate()
        behaviorTimer = nil
        if stopPointerTracking {
            pointerTimer?.invalidate()
            pointerTimer = nil
        }
        scene.isPaused = true
        spriteView.isPaused = true
        scene.setPlaybackPaused(true)
        if stopPointerTracking { setIgnoresMouseEvents(true) }
    }

    private func scheduleBehaviorTimer() {
        behaviorTimer?.invalidate()
        guard !settings.hidden, !settings.paused else {
            behaviorTimer = nil
            return
        }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / Double(behaviorFramesPerSecond), repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        behaviorTimer = timer
    }

    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        updateMousePassthrough()
    }

    private func applyBehavior(_ state: PetBehaviorState) {
        scene.setBehavior(state)
        let frameRate = PetBehaviorController.frameRate(for: state, quiet: settings.quiet)
        guard behaviorFramesPerSecond != frameRate else { return }
        behaviorFramesPerSecond = frameRate
        if behaviorTimer != nil { scheduleBehaviorTimer() }
    }

    private func tick() {
        guard panel.isVisible, !settings.paused, !panel.inLiveResize else { return }
        guard let screen = screenContainingMost(of: panel.frame) else {
            recoverAfterEnvironmentChange()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(max(now - lastTick, 0), 0.1)
        lastTick = now

        if !settings.quiet,
           let nextState = behavior.step(
               deltaTime: dt * settings.activity.behaviorClockScale,
               choice: Double.random(in: 0...1)
           ) {
            applyBehavior(nextState)
        }

        let visible = screen.visibleFrame
        let upperX = max(visible.minX, visible.maxX - panelSize.width)
        let x = motion.step(
            deltaTime: dt,
            range: visible.minX...upperX,
            active: scene.locomotionIsActive && !settings.quiet
        )
        scene.setFacing(direction: motion.direction)
        patrolY = min(max(patrolY, visible.minY), max(visible.minY, visible.maxY - panelSize.height))
        let origin = ScreenClamp.origin(
            CGPoint(x: x, y: patrolY),
            size: panelSize,
            inside: visible
        )
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }

        if now - lastPositionSave >= 2.5 {
            persistPosition(on: screen)
            lastPositionSave = now
        }
    }

    private func updateMousePassthrough() {
        guard panel.isVisible else {
            setIgnoresMouseEvents(true)
            return
        }
        if dragging {
            setIgnoresMouseEvents(false)
            return
        }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        setIgnoresMouseEvents(!scene.isPointInsidePet(local))
    }

    private func setIgnoresMouseEvents(_ ignores: Bool) {
        guard cachedIgnoresMouseEvents != ignores else { return }
        cachedIgnoresMouseEvents = ignores
        panel.ignoresMouseEvents = ignores
    }

    private func makeMotion(position: CGFloat, direction: CGFloat) -> NaturalPatrol {
        NaturalPatrol(
            position: position,
            direction: direction,
            maximumSpeed: settings.activity.maximumSpeed,
            acceleration: settings.activity == .active ? 38 : 28,
            turnPauseDuration: 1.15
        )
    }

    private func persistPosition(on explicitScreen: NSScreen? = nil) {
        guard panel != nil else { return }
        guard let screen = explicitScreen ?? screenContainingMost(of: panel.frame) else { return }
        let visible = screen.visibleFrame
        let travelX = max(visible.width - panel.frame.width, 1)
        let travelY = max(visible.height - panel.frame.height, 1)
        let normalizedX = Double((panel.frame.minX - visible.minX) / travelX)
        let normalizedY = Double((panel.frame.minY - visible.minY) / travelY)
        settings.savePosition(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            screenIdentifier: screenIdentifier(screen)
        )
    }

    private func restoredScreen() -> NSScreen? {
        guard let identifier = settings.screenIdentifier else { return nil }
        return NSScreen.screens.first { screenIdentifier($0) == identifier }
    }

    private func restoredOrigin(on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        guard settings.screenIdentifier != nil else {
            return ScreenClamp.origin(
                CGPoint(
                    x: visible.maxX - panelSize.width - 24,
                    y: visible.minY + 12
                ),
                size: panelSize,
                inside: visible
            )
        }
        let travelX = max(visible.width - panelSize.width, 0)
        let travelY = max(visible.height - panelSize.height, 0)
        return ScreenClamp.origin(
            CGPoint(
                x: visible.minX + travelX * CGFloat(settings.normalizedX),
                y: visible.minY + travelY * CGFloat(settings.normalizedY)
            ),
            size: panelSize,
            inside: visible
        )
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private func screenContainingMost(of frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }

    private func recoverAfterEnvironmentChange() {
        guard !NSScreen.screens.isEmpty else { return }
        let screen = screenContainingMost(of: panel.frame) ?? restoredScreen() ?? screenUnderMouse
        let recovered = ScreenClamp.frame(panel.frame, inside: screen.visibleFrame)
        panel.setFrame(recovered, display: true)
        patrolY = recovered.minY
        motion = makeMotion(position: recovered.minX, direction: motion?.direction ?? -1)
        persistPosition(on: screen)
    }

    private func syncMenuState() {
        quietItem?.state = settings.quiet ? .on : .off
        pauseItem?.title = settings.paused ? "继续" : "暂停"
        visibilityItem?.title = settings.hidden ? "显示豆花" : "隐藏豆花"
        for preset in PetSizePreset.allCases {
            sizeItems[preset]?.state = settings.size == preset ? .on : .off
        }
        for preset in PetActivityPreset.allCases {
            activityItems[preset]?.state = settings.activity == preset ? .on : .off
        }
    }

    func sceneWasPetted() {
        behavior = PetBehaviorController(state: .observing, duration: 18)
        applyBehavior(.observing)
    }

    func sceneDragBegan(at screenPoint: CGPoint) {
        dragging = true
        dragOffset = CGPoint(
            x: screenPoint.x - panel.frame.minX,
            y: screenPoint.y - panel.frame.minY
        )
    }

    func sceneDragged(to screenPoint: CGPoint) {
        panel.setFrameOrigin(
            CGPoint(x: screenPoint.x - dragOffset.x, y: screenPoint.y - dragOffset.y)
        )
    }

    func sceneDragEnded() {
        dragging = false
        let screen = screenContainingMost(of: panel.frame) ?? screenUnderMouse
        let frame = ScreenClamp.frame(panel.frame, inside: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        patrolY = frame.minY
        motion = makeMotion(position: frame.minX, direction: motion.direction)
        persistPosition(on: screen)
        updateMousePassthrough()
    }

    func sceneRequestedContextMenu(at screenPoint: CGPoint) {
        statusMenu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    @objc private func callHome() {
        settings.hidden = false
        settings.paused = false
        let screen = screenUnderMouse
        let target = CGPoint(
            x: screen.visibleFrame.maxX - panelSize.width - 24,
            y: screen.visibleFrame.minY + 12
        )
        let origin = ScreenClamp.origin(target, size: panelSize, inside: screen.visibleFrame)
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
        panel.orderFrontRegardless()
        patrolY = origin.y
        motion = makeMotion(position: origin.x, direction: -1)
        behavior = PetBehaviorController(state: .observing, duration: 18)
        applyBehavior(.observing)
        persistPosition(on: screen)
        startRuntime()
        syncMenuState()
    }

    @objc private func toggleQuiet(_ sender: NSMenuItem) {
        settings.quiet.toggle()
        if settings.quiet {
            behavior = PetBehaviorController(state: .loafing, duration: 120)
            applyBehavior(.loafing)
        } else {
            behavior = PetBehaviorController(state: .observing, duration: 18)
            applyBehavior(.observing)
        }
        syncMenuState()
    }

    @objc private func togglePaused() {
        settings.paused.toggle()
        if settings.paused {
            stopRuntime(stopPointerTracking: false)
        } else {
            startRuntime()
        }
        syncMenuState()
    }

    @objc private func toggleVisible() {
        if settings.hidden {
            settings.hidden = false
            panel.orderFrontRegardless()
            startRuntime()
        } else {
            persistPosition()
            settings.hidden = true
            panel.orderOut(nil)
            stopRuntime(stopPointerTracking: true)
        }
        syncMenuState()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let preset = PetSizePreset(rawValue: rawValue),
            preset != settings.size
        else { return }

        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        settings.size = preset
        let newSize = panelSize
        var frame = CGRect(
            x: center.x - newSize.width * 0.5,
            y: center.y - newSize.height * 0.5,
            width: newSize.width,
            height: newSize.height
        )
        let screen = screenContainingMost(of: frame) ?? screenUnderMouse
        frame = ScreenClamp.frame(frame, inside: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        spriteView.frame = CGRect(origin: .zero, size: newSize)
        scene.size = newSize
        patrolY = frame.minY
        motion = makeMotion(position: frame.minX, direction: motion.direction)
        persistPosition(on: screen)
        syncMenuState()
    }

    @objc private func selectActivity(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let preset = PetActivityPreset(rawValue: rawValue)
        else { return }
        settings.activity = preset
        motion = makeMotion(position: panel.frame.minX, direction: motion.direction)
        syncMenuState()
    }

    @objc private func resetSettings() {
        settings.reset()
        let newSize = panelSize
        panel.setContentSize(newSize)
        spriteView.frame = CGRect(origin: .zero, size: newSize)
        scene.size = newSize
        callHome()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "豆花 / DouhuaPet"
        alert.informativeText = "写实、离线、原生的 macOS 豆花桌面宠物。形象依据豆花本人的照片制作；应用运行时不联网、不上传素材，也不申请辅助功能、输入监控或屏幕录制权限。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func quit() {
        persistPosition()
        NSApp.terminate(nil)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
withExtendedLifetime(delegate) {}
