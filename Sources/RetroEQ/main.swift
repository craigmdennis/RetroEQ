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

    /// Debug aid: drives the real menu items, measures tones through the live tap,
    /// hides the window, measures again, then restores the user's settings and quits.
    private func selfTest() {
        let saved = (gains: model.gains, preamp: model.preamp, preset: model.presetName, enabled: model.enabled)
        let outputBefore = (try? AudioDevices.defaultOutput()) ?? 0
        var failures = 0
        func expect(_ ok: Bool, _ what: String) {
            print((ok ? "PASS  " : "FAIL  ") + what)
            if !ok { failures += 1 }
        }

        let dir = FileManager.default.temporaryDirectory
        func tone(_ freq: Double) -> URL {
            let url = dir.appendingPathComponent("retroeq-\(Int(freq)).wav")
            let rate = 48000, count = rate * 3 / 2
            var data = Data()
            func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
            func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
            data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + count * 2))
            data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
            data.append(contentsOf: Array("data".utf8)); u32(UInt32(count * 2))
            for i in 0..<count {
                let fade = min(1, Double(min(i, count - i)) / 960)
                let v = 0.3 * fade * sin(2 * .pi * freq * Double(i) / Double(rate))
                u16(UInt16(bitPattern: Int16(v * 32767)))
            }
            try? data.write(to: url)
            return url
        }
        let low = tone(62.5), mid = tone(1000)

        /// Plays a tone and returns the live EQ gain (output vs input) at its frequency, in dB.
        func measure(_ url: URL, _ freq: Double, _ done: @escaping (Double) -> Void) {
            let player = Process()
            player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            player.arguments = ["-v", "0.2", url.path]
            try? player.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { eq_probe_start(self.model.engine, freq) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                var inMag = 0.0, outMag = 0.0
                eq_probe_read(self.model.engine, &inMag, &outMag)
                eq_probe_start(self.model.engine, 0)
                player.waitUntilExit()
                done(inMag > 1e-6 ? 20 * log10(outMag / inMag) : -.infinity)
            }
        }

        func statusMenuItem(_ prefix: String) -> (NSMenu, Int)? {
            guard let menu = statusItem.menu else { return nil }
            menuNeedsUpdate(menu)
            guard let i = menu.items.firstIndex(where: { $0.title.hasPrefix(prefix) }) else { return nil }
            return (menu, i)
        }
        func click(_ prefix: String) {
            guard let (menu, i) = statusMenuItem(prefix) else { return expect(false, "menu item \(prefix) exists") }
            menu.performActionForItem(at: i)
        }
        func choosePreset(_ name: String) {
            guard let (menu, i) = statusMenuItem("Preset:"), let sub = menu.items[i].submenu,
                  let j = sub.items.firstIndex(where: { $0.title == name }) else { return expect(false, "preset \(name) in menu") }
            sub.performActionForItem(at: j)
        }

        func near(_ v: Double, _ target: Double) -> Bool { abs(v - target) < 1.0 }
        let expectBoostLow = eq_response_db(Preset.all[1].gains, 62.5) + Double(Preset.all[1].preamp)
        let expectBoostMid = eq_response_db(Preset.all[1].gains, 1000) + Double(Preset.all[1].preamp)

        func step1() {
            if !model.enabled { click("Equalizer On") } // the user's saved state may be off
            expect(model.enabled && model.isProcessing, "EQ on and the tap running")
            click("Equalizer On")
            expect(!model.enabled && !model.isProcessing, "menu: Equalizer On toggles the EQ off")
            measure(low, 62.5) { g in
                expect(g == -.infinity, "with the EQ off, no audio goes through the EQ")
                click("Equalizer On")
                expect(self.model.enabled && self.model.isProcessing, "menu: Equalizer On toggles the EQ back on")
                step2()
            }
        }
        func step2() {
            choosePreset("Flat")
            expect(model.presetName == "Flat", "menu: preset Flat applied")
            measure(low, 62.5) { flatLow in measure(mid, 1000) { flatMid in
                expect(near(flatLow, 0) && near(flatMid, 0),
                       String(format: "Flat, live: 62 Hz %+.1f dB, 1 kHz %+.1f dB (expect 0)", flatLow, flatMid))
                choosePreset("Bass Boost")
                expect(self.model.presetName == "Bass Boost", "menu: preset Bass Boost applied")
                measure(low, 62.5) { boostLow in measure(mid, 1000) { boostMid in
                    expect(near(boostLow, expectBoostLow) && near(boostMid, expectBoostMid),
                           String(format: "Bass Boost, live: 62 Hz %+.1f dB, 1 kHz %+.1f dB (expect %+.1f, %+.1f) -> bass %+.1f dB over mids",
                                  boostLow, boostMid, expectBoostLow, expectBoostMid, boostLow - boostMid))
                    self.model.setGain(1, 12)
                    measure(low, 62.5) { sliderLow in
                        expect(sliderLow - boostLow > 3, String(format: "62 Hz slider to +12 dB, live: 62 Hz %+.1f dB (was %+.1f)", sliderLow, boostLow))
                        step3()
                    }
                }}
            }}
        }
        func step3() {
            choosePreset("Bass Boost")
            hideWindow()
            expect(!window.isVisible, "close/hide: window is hidden")
            expect(model.enabled && model.isProcessing, "close/hide: EQ still on and tap still running")
            measure(low, 62.5) { hiddenLow in measure(mid, 1000) { hiddenMid in
                expect(near(hiddenLow, expectBoostLow) && near(hiddenMid, expectBoostMid),
                       String(format: "close/hide, live: 62 Hz %+.1f dB, 1 kHz %+.1f dB (Bass Boost still applied)", hiddenLow, hiddenMid))
                let outputAfter = (try? AudioDevices.defaultOutput()) ?? 0
                expect(outputAfter == outputBefore, "system default output device unchanged (\(AudioDevices.name(outputAfter)))")
                self.model.restore(gains: saved.gains, preamp: saved.preamp, presetName: saved.preset, enabled: saved.enabled)
                print(failures == 0 ? "SELFTEST PASSED" : "SELFTEST FAILED (\(failures))")
                self.model.shutdown()
                exit(failures == 0 ? 0 : 2)
            }}
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { step1() }
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
