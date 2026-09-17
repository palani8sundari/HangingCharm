import AppKit
import QuartzCore

/// A clear, click-through panel over the whole display, on every Space.
final class CharmPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Runs the charm: where its hook is, the physics loop, and the pointer.
final class CharmController: NSObject {
    var menuProvider: (() -> NSMenu)?
    /// Told when the charm comes down onto its thread (true) or has been wound away into the menu bar (false).
    var onHangingChanged: ((Bool) -> Void)?

    private let settings: Settings
    private let statusItem: NSStatusItem
    private let panel = CharmPanel()
    private let view = CharmView(frame: .zero)
    private let physics = CordPhysics()
    private let rope = RopeChain()

    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var accumulator = 0.0
    private let fixedStep = 1.0 / 240.0

    private var hook: CGPoint?                  // global coordinates of the top of the hook
    private var displayID: CGDirectDisplayID?
    private var isShowing = false
    private var changesWhenReeledIn: [() -> Void] = []
    private var hideWhenReeledIn = false

    private var isDragging = false
    private var isRehanging = false
    private var pointerDownAt: TimeInterval = 0
    private var pointerTravel: CGFloat = 0
    private var lastPointer = CGPoint.zero
    private var rehangOffset: CGFloat = 0

    private var timers: [Timer] = []
    private var monitors: [Any] = []
    private var ticks = 0

    init(settings: Settings, statusItem: NSStatusItem) {
        self.settings = settings
        self.statusItem = statusItem
        super.init()
    }

    func start() {
        panel.contentView = view
        view.controller = self
        view.charm = Charm.with(id: settings.charmID)
        view.sizeFactor = settings.size.factor
        physics.length = settings.cordLength.points
        physics.airDrag = settings.swing.damping

        let link = view.displayLink(target: self, selector: #selector(advance(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        displayLink = link

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                self?.updateHover()
            },
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.updateHover()
                return event
            },
        ].compactMap { $0 }

        // A steady check as well, so the charm is always ready to be grabbed.
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        if settings.isVisible { show() }
    }

    // MARK: Settings

    func settingsChanged(_ change: Settings.Change) {
        switch change {
        case .visibility:
            settings.isVisible ? show() : hide()
        case .charm:
            swap(to: Charm.with(id: settings.charmID))
        case .cord:
            physics.length = settings.cordLength.points     // the charm drops or springs up to the new length
            wake()
        case .size:
            whenReeledIn { [weak self] in
                guard let self else { return }
                self.view.sizeFactor = self.settings.size.factor
            }
        case .swing:
            physics.airDrag = settings.swing.damping
        case .placement:
            refreshHook()
        }
    }

    func flick() {
        guard isShowing else { return }
        physics.flick()
        wake()
    }

    // MARK: Showing, hiding, swapping

    private func show() {
        isShowing = true
        hideWhenReeledIn = false
        onHangingChanged?(true)
        refreshHook(force: true)
        if !panel.isVisible {
            physics.reset(reeledIn: true)
            rope.reset(to: physics.position)
            panel.orderFrontRegardless()
        }
        if changesWhenReeledIn.isEmpty { lower() }
    }

    private func hide() {
        isShowing = false
        guard panel.isVisible else { return onHangingChanged?(false) ?? () }
        hideWhenReeledIn = true
        reelIn()
    }

    private func swap(to charm: Charm) {
        guard charm != view.charm || !changesWhenReeledIn.isEmpty else { return flick() }
        whenReeledIn { [weak self] in self?.view.charm = charm }
    }

    /// Winds the charm up into the hook, makes `change` out of sight, and lowers it again.
    private func whenReeledIn(_ change: @escaping () -> Void) {
        guard isShowing, panel.isVisible else { return change() }
        changesWhenReeledIn.append(change)
        reelIn()
    }

    private func reelIn() {
        physics.reelTarget = 0.04
        wake()
    }

    private func lower() {
        physics.reelTarget = 1
        wake()
    }

    private func reachedHook() {
        let changes = changesWhenReeledIn
        changesWhenReeledIn = []
        changes.forEach { $0() }
        if hideWhenReeledIn {
            hideWhenReeledIn = false
            panel.orderOut(nil)
            displayLink?.isPaused = true
            onHangingChanged?(false)
        } else {
            lower()
        }
    }

    // MARK: Frame loop

    private func wake() {
        guard let link = displayLink, link.isPaused else { return }
        lastFrame = 0
        accumulator = 0
        link.isPaused = false
    }

    @objc private func advance(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrame == 0 ? 1.0 / 60.0 : clamp(now - lastFrame, 0, 0.05)
        lastFrame = now
        accumulator += dt
        var steps = 0
        while accumulator >= fixedStep && steps < 14 {
            physics.step(fixedStep)
            rope.step(fixedStep, to: physics.position, naturalLength: physics.naturalLength * physics.reel,
                      grip: physics.cordGrip, gravity: physics.gravity)
            accumulator -= fixedStep
            steps += 1
        }

        if physics.reelTarget < 0.5 && physics.reel < 0.07 && isReelingForChange {
            reachedHook()
            if !panel.isVisible { return }
        }

        // Fade as it winds up, so it seems to disappear into the hook.
        view.charmOpacity = Float(clamp((physics.reel - 0.08) / 0.35, 0, 1))
        view.render(physics, rope: rope)
        updateHover()

        if physics.isSettled && !isDragging && physics.reelTarget > 0.5 {
            link.isPaused = true
            lastFrame = 0
        }
    }

    private var isReelingForChange: Bool { hideWhenReeledIn || !changesWhenReeledIn.isEmpty }

    private func tick() {
        updateHover()
        ticks += 1
        guard ticks % 5 == 0, isShowing else { return }
        if !isDragging { refreshHook() }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if settings.breeze && !reduceMotion && displayLink?.isPaused == true && Double.random(in: 0..<1) < 0.25 / 20 {
            physics.nudge(strength: .random(in: 0.03...0.07))
            wake()
        }
    }

    // MARK: Where the hook goes

    @objc private func screensChanged() { refreshHook(force: true) }

    @objc private func spaceChanged() {
        if isShowing { panel.orderFrontRegardless() }
    }

    private func refreshHook(force: Bool = false) {
        guard let target = hookPosition() else { return }
        let newDisplay = target.screen.displayID
        let changedDisplay = displayID != nil && newDisplay != displayID
        if let old = hook, !force, !changedDisplay {
            let dx = target.point.x - old.x
            if abs(dx) < 0.5 && abs(target.point.y - old.y) < 0.5 { return }
            if abs(dx) < 300 { moveHook(by: Double(dx)) }
        }
        hook = target.point
        displayID = newDisplay
        place(on: target.screen, hook: target.point)
        if changedDisplay && isShowing && panel.isVisible {
            // Moving to another display: hang it fresh there.
            physics.reset(reeledIn: true)
            rope.reset(to: physics.position)
            lower()
        }
        view.render(physics, rope: rope)
        wake()
    }

    private func moveHook(by dx: Double) {
        physics.hookMoved(dx: dx)
        rope.hookMoved(dx: dx)
    }

    /// The hook sits just under this app's menu bar icon (or wherever it was
    /// last ⌥-dragged to), on the display the pointer is on.
    private func hookPosition() -> (screen: NSScreen, point: CGPoint)? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let iconFrame = statusItem.button?.window?.frame ?? .zero
        let iconScreen = screens.first { $0.frame.intersects(iconFrame) }

        var target = iconScreen ?? primary
        if settings.followsPointerAcrossDisplays,
           let pointerScreen = screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            target = pointerScreen
        }

        var fromRight: CGFloat = 360
        if let iconScreen, iconFrame.width > 0 {
            let offset = iconScreen.frame.maxX - iconFrame.midX
            if offset > 0 && offset < iconScreen.frame.width { fromRight = offset }
        }
        if settings.hangPoint == .custom, let custom = settings.customOffsetFromRight {
            fromRight = CGFloat(custom)
        }
        fromRight = clamp(fromRight, 24, target.frame.width - 24)

        let menuBarHeight = max(0, target.frame.maxY - target.visibleFrame.maxY)
        return (target, CGPoint(x: target.frame.maxX - fromRight, y: target.frame.maxY - menuBarHeight + 1))
    }

    private func place(on screen: NSScreen, hook: CGPoint) {
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        if view.frame.size != screen.frame.size { view.frame = CGRect(origin: .zero, size: screen.frame.size) }
        view.pivot = CGPoint(x: hook.x - screen.frame.minX, y: screen.frame.maxY - hook.y + CharmView.pivotDrop)
    }

    // MARK: Pointer

    /// The panel only takes the mouse while the pointer is on the charm or its cord.
    private func updateHover() {
        guard panel.isVisible else { return }
        var wantsMouse = isDragging
        if !wantsMouse {
            let pointer = NSEvent.mouseLocation, frame = panel.frame
            if frame.contains(pointer) {
                let q = CGPoint(x: pointer.x - frame.minX, y: frame.maxY - pointer.y)
                wantsMouse = view.charmContains(q) || view.cordFraction(at: q) != nil
            }
        }
        if panel.ignoresMouseEvents == wantsMouse { panel.ignoresMouseEvents = !wantsMouse }
    }

    private func local(_ p: CGPoint) -> Vec { Vec(p) - Vec(view.pivot) }

    func pointerDown(_ event: NSEvent) {
        let p = view.modelPoint(event)
        let onCharm = view.charmContains(p)
        let cordFraction = onCharm ? nil : view.cordFraction(at: p)
        guard onCharm || cordFraction != nil else { return }

        isDragging = true
        isRehanging = event.modifierFlags.contains(.option)
        pointerDownAt = event.timestamp
        pointerTravel = 0
        lastPointer = NSEvent.mouseLocation
        if isRehanging {
            rehangOffset = lastPointer.x - (hook?.x ?? lastPointer.x)
        } else if let cordFraction {
            physics.grabCord(fraction: cordFraction, at: local(p))
        } else {
            physics.grabCharm(at: local(p))
        }
        wake()
    }

    func pointerDragged(_ event: NSEvent) {
        guard isDragging else { return }
        let pointer = NSEvent.mouseLocation
        pointerTravel += hypot(pointer.x - lastPointer.x, pointer.y - lastPointer.y)
        lastPointer = pointer

        if isRehanging {
            guard var moved = hook, let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return }
            let x = clamp(pointer.x - rehangOffset, screen.frame.minX + 24, screen.frame.maxX - 24)
            moveHook(by: Double(x - moved.x))
            moved.x = x
            hook = moved
            place(on: screen, hook: moved)
        } else {
            physics.pointer = local(view.modelPoint(event))
        }
        wake()
    }

    func pointerUp(_ event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        if isRehanging {
            isRehanging = false
            if let hook, let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
                settings.customOffsetFromRight = Double(screen.frame.maxX - hook.x)
                settings.hangPoint = .custom
            }
        } else {
            let wasTap = event.timestamp - pointerDownAt < 0.3 && pointerTravel < 4
            physics.release()
            if wasTap { physics.flick() }
        }
        wake()
        updateHover()
    }

    func showContextMenu(for event: NSEvent, in view: NSView) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
