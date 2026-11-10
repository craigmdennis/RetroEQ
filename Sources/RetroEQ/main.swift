import AppKit
import EQDSP
import SwiftUI

/// Borderless window with square corners that can still take keyboard focus.
final class SkinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// NSMenuItem target that holds a Swift closure.
final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

extension NSMenuItem {
    convenience init(title: String, checked: Bool = false, key: String = "", handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(MenuAction.fire), keyEquivalent: key)
        let action = MenuAction(handler)
        target = action
        representedObject = action // NSMenuItem.target is weak; this keeps the closure alive
        state = checked ? .on : .off
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = EQModel()
    private lazy var meter = LevelMeter(model: model)
    private var window: SkinWindow!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildWindow()
        buildStatusItem()
        showWindow()
        if let path = ProcessInfo.processInfo.environment["RETROEQ_SNAPSHOT"] { snapshot(to: path) }
        if ProcessInfo.processInfo.environment["RETROEQ_SELFTEST"] != nil { selfTest() }
    }

    /// Debug aid: plays a quiet system sound and reports whether it came back through the EQ.
    private func selfTest() {
        var maxPeak: Float = 0
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0.15", "/System/Library/Sounds/Submarine.aiff"]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { try? player.run() }
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            var l: Float = 0, r: Float = 0
            eq_read_peaks(self.model.engine, &l, &r)
            maxPeak = max(maxPeak, l, r)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            print("SELFTEST enabled=\(self.model.enabled) output=\(self.model.outputName) error=\(self.model.errorMessage ?? "none") peak=\(maxPeak)")
            self.model.shutdown()
            exit(maxPeak > 0 ? 0 : 2)
        }
    }

    /// Debug aid: renders the window to a PNG and quits (audio is never started in this mode).
    private func snapshot(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let view = self.window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Window

    private func buildWindow() {
        window = SkinWindow(contentRect: .zero, styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.backgroundColor = NSColor(Skin.body)
        window.title = "RetroEQ"
        let root = EQWindowView(
            model: model,
            meter: meter,
            onMinimize: { [weak self] in self?.window.miniaturize(nil) },
            onClose: { [weak self] in self?.hideWindow() },
            showPresets: { [weak self] in self?.popUpPresets() }
        )
        let hosting = NSHostingView(rootView: root)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        if !window.setFrameUsingName("RetroEQMain") { window.center() }
        window.setFrameAutosaveName("RetroEQMain")
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func hideWindow() {
        window.orderOut(nil)
    }

    private func popUpPresets() {
        let menu = NSMenu()
        addPresetItems(to: menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func addPresetItems(to menu: NSMenu) {
        for preset in Preset.all {
            menu.addItem(NSMenuItem(title: preset.name, checked: preset.name == model.presetName) { [weak self] in
                self?.model.apply(preset)
            })
        }
    }

    // MARK: Menus

    private func buildMainMenu() {
        // No menu bar is shown (LSUIElement), but these give us ⌘W / ⌘Q.
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Hide Equalizer", key: "w") { [weak self] in self?.hideWindow() })
        appMenu.addItem(NSMenuItem(title: "Quit RetroEQ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "RetroEQ")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "Show Equalizer") { [weak self] in self?.showWindow() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Equalizer On", checked: model.enabled) { [weak self] in
            guard let self else { return }
            self.model.setEnabled(!self.model.enabled)
        })
        let presetsItem = NSMenuItem(title: "Preset: \(model.presetName)", action: nil, keyEquivalent: "")
        let presets = NSMenu()
        addPresetItems(to: presets)
        presetsItem.submenu = presets
        menu.addItem(presetsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Launch at Login", checked: model.launchesAtLogin) { [weak self] in
            guard let self else { return }
            self.model.setLaunchesAtLogin(!self.model.launchesAtLogin)
        })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit RetroEQ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
