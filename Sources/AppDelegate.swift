import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var controller: CharmController!
    private var hotKeys: HotKeys?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "HangingCharmHook"
        statusItem.button?.toolTip = "Hanging Charm"
        updateMenuBarIcon(hanging: settings.isVisible)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller = CharmController(settings: settings, statusItem: statusItem)
        controller.menuProvider = { [weak self] in
            let menu = NSMenu()
            self?.populate(menu)
            return menu
        }
        controller.onHangingChanged = { [weak self] hanging in self?.updateMenuBarIcon(hanging: hanging) }
        settings.onChange = { [weak self] change in
            guard let self else { return }
            self.controller.settingsChanged(change)
            if change == .charm && !self.settings.isVisible { self.updateMenuBarIcon(hanging: false) }
        }

        hotKeys = HotKeys([
            .init(keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey) { [weak self] in self?.flick() },
            .init(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey) { [weak self] in self?.toggleVisible() },
        ])
        openAtLoginByDefault()

        // Let the menu bar place the icon first, so the cord starts right under it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.controller.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !settings.isVisible { settings.isVisible = true } else { controller.flick() }
        return false
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.autoenablesItems = false

        let show = ActionItem("Hang on Thread", key: "h") { [weak self] in self?.toggleVisible() }
        show.keyEquivalentModifierMask = [.control, .option]
        show.state = settings.isVisible ? .on : .off
        menu.addItem(show)

        let flick = ActionItem("Give It a Flick", key: "f") { [weak self] in self?.flick() }
        flick.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(flick)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Charm"))
        for charm in Charm.all {
            let row = ActionItem(charm.name) { [weak self] in
                guard let self else { return }
                self.settings.charmID = charm.id
                if !self.settings.isVisible { self.settings.isVisible = true }
            }
            row.image = charm.menuImage()
            if #available(macOS 14.4, *) { row.subtitle = charm.region }
            row.state = charm.id == settings.charmID ? .on : .off
            menu.addItem(row)
        }
        menu.addItem(ActionItem("Add Your Own Picture…") { [weak self] in self?.addPicture() })
        let customs = CustomCharms.shared.charms
        if !customs.isEmpty {
            let remove = NSMenuItem(title: "Remove Your Picture", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for charm in customs {
                let row = ActionItem(charm.name) { [weak self] in self?.removePicture(charm) }
                row.image = charm.menuImage(side: 20)
                submenu.addItem(row)
            }
            remove.submenu = submenu
            menu.addItem(remove)
        }

        menu.addItem(.separator())
        menu.addItem(choices("Cord Length", CordLength.allCases, selected: settings.cordLength, title: \.title) {
            [weak self] in self?.settings.cordLength = $0
        })
        menu.addItem(choices("Size", CharmSize.allCases, selected: settings.size, title: \.title) {
            [weak self] in self?.settings.size = $0
        })
        menu.addItem(choices("Swing", Swing.allCases, selected: settings.swing, title: \.title) {
            [weak self] in self?.settings.swing = $0
        })
        menu.addItem(hangFromMenu())

        menu.addItem(.separator())
        let follow = ActionItem("Follow Me Across Displays") { [weak self] in
            self?.settings.followsPointerAcrossDisplays.toggle()
        }
        follow.state = settings.followsPointerAcrossDisplays ? .on : .off
        menu.addItem(follow)

        let breeze = ActionItem("Gentle Breeze") { [weak self] in self?.settings.breeze.toggle() }
        breeze.state = settings.breeze ? .on : .off
        menu.addItem(breeze)

        let loginStatus = SMAppService.mainApp.status
        let login = ActionItem(loginStatus == .requiresApproval ? "Open at Login (Approve in System Settings…)" : "Open at Login") {
            [weak self] in self?.toggleOpenAtLogin()
        }
        login.state = loginStatus == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hint.attributedTitle = NSAttributedString(
            string: "Pull the charm or its thread, then let go.\n⌥-drag the charm to move its hook.",
            attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(ActionItem("Quit Hanging Charm", key: "q") { NSApp.terminate(nil) })
    }

    private func choices<T: Equatable>(_ title: String, _ options: [T], selected: T, title name: KeyPath<T, String>,
                                       choose: @escaping (T) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for option in options {
            let row = ActionItem(option[keyPath: name]) { choose(option) }
            row.state = option == selected ? .on : .off
            submenu.addItem(row)
        }
        parent.submenu = submenu
        return parent
    }

    private func hangFromMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Hang From", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let icon = ActionItem("Its Menu Bar Icon") { [weak self] in self?.settings.hangPoint = .menuBarIcon }
        icon.state = settings.hangPoint == .menuBarIcon ? .on : .off
        let custom = ActionItem("Where I Last Moved It") { [weak self] in self?.settings.hangPoint = .custom }
        custom.state = settings.hangPoint == .custom ? .on : .off
        custom.isEnabled = settings.customOffsetFromRight != nil
        submenu.addItem(icon)
        submenu.addItem(custom)
        parent.submenu = submenu
        return parent
    }

    // MARK: Actions

    /// While the charm hangs, the menu bar shows the hook its thread hangs from;
    /// once it is wound away, the charm itself sits up in the menu bar.
    private func updateMenuBarIcon(hanging: Bool) {
        let charmIcon = Charm.with(id: settings.charmID).menuImage(side: 20)
        statusItem.button?.image = hanging ? MenuBarIcon.hook() : (charmIcon ?? MenuBarIcon.make())
    }

    private func addPicture() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Choose a Picture to Hang"
        panel.prompt = "Hang It"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder = CustomCharms.shared.folder
        let names = Charm.all.map(\.name)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try CustomCharms.make(from: url, in: folder, existingNames: names) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let id):
                    CustomCharms.shared.reload()
                    self.settings.charmID = id
                    if !self.settings.isVisible { self.settings.isVisible = true }
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "That picture couldn’t be hung"
                    alert.informativeText = error.localizedDescription
                    NSApp.activate()
                    alert.runModal()
                }
            }
        }
    }

    private func removePicture(_ charm: Charm) {
        if settings.charmID == charm.id { settings.charmID = Charm.builtIn[0].id }
        CustomCharms.shared.remove(charm)
    }

    private func toggleVisible() { settings.isVisible.toggle() }

    private func flick() {
        if settings.isVisible { controller.flick() } else { settings.isVisible = true }
    }

    private func openAtLoginByDefault() {
        let key = "openAtLoginDefaultApplied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Open at Login couldn’t be changed"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can add Hanging Charm yourself in System Settings › General › Login Items."
            NSApp.activate()
            alert.runModal()
        }
    }
}

/// A menu item that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// Menu bar glyphs, drawn as template images.
enum MenuBarIcon {
    /// The hook the thread hangs from, with the start of the cord.
    static func hook() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            NSBezierPath(roundedRect: NSRect(x: 5.5, y: 1.5, width: 7, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 9, y: 3.6))
            stem.line(to: NSPoint(x: 9, y: 6))
            stem.lineWidth = 1.4
            stem.stroke()
            let eye = NSBezierPath(ovalIn: NSRect(x: 6.6, y: 6, width: 4.8, height: 4.8))
            eye.lineWidth = 1.4
            eye.stroke()
            let cord = NSBezierPath()
            cord.move(to: NSPoint(x: 9, y: 10.8))
            cord.line(to: NSPoint(x: 9, y: 18))
            cord.lineWidth = 1.2
            cord.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A little eye charm on its hook, for when no charm artwork is available.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let eye = NSBezierPath(ovalIn: NSRect(x: 7.1, y: 0.9, width: 3.8, height: 3.8))
            eye.lineWidth = 1.2
            eye.stroke()
            let cord = NSBezierPath()
            cord.move(to: NSPoint(x: 9, y: 4.8))
            cord.line(to: NSPoint(x: 9, y: 7.8))
            cord.lineWidth = 1.2
            cord.stroke()
            NSBezierPath(ovalIn: NSRect(x: 4.3, y: 7.7, width: 9.4, height: 9.4)).fill()
            guard let context = NSGraphicsContext.current else { return true }
            context.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 6.35, y: 9.75, width: 5.3, height: 5.3)).fill()
            context.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: 7.75, y: 11.15, width: 2.5, height: 2.5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
