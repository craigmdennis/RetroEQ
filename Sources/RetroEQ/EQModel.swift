import Combine
import EQDSP
import Foundation
import ServiceManagement

final class EQModel: ObservableObject {
    static let bandLabels = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let range: Float = 12

    @Published private(set) var gains: [Float] = Preset.flat.gains
    @Published private(set) var preamp: Float = 0
    @Published private(set) var enabled = false
    @Published private(set) var presetName = Preset.flat.name
    @Published private(set) var outputName = "—"
    @Published private(set) var errorMessage: String?
    @Published private(set) var ticker: String?

    let engine: OpaquePointer
    private let tap: SystemAudioTap
    private var tickerClear: DispatchWorkItem?
    private let defaults = UserDefaults.standard
    /// Snapshot mode renders the window only: it never starts audio or writes settings.
    private let snapshotMode = ProcessInfo.processInfo.environment["RETROEQ_SNAPSHOT"] != nil

    init() {
        engine = eq_create()
        tap = SystemAudioTap(engine: engine)
        tap.onDeviceChange = { [weak self] in self?.outputDeviceChanged() }
        load()
        if snapshotMode, let name = ProcessInfo.processInfo.environment["RETROEQ_SNAPSHOT_PRESET"],
           let preset = Preset.all.first(where: { $0.name == name }) {
            gains = preset.gains
            preamp = preset.preamp
            presetName = preset.name
            enabled = true
        }
        pushToEngine()
        refreshOutputName()
        if enabled && !snapshotMode { startAudio() }
    }

    // MARK: Controls

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "enabled")
        if on { startAudio() } else { tap.stop(); errorMessage = nil }
    }

    func setGain(_ band: Int, _ value: Float) {
        guard gains[band] != value else { return }
        gains[band] = value
        eq_set_band_gain(engine, Int32(band), value)
        markCustom()
        flash(String(format: "%@ HZ  %+.1f DB", Self.bandLabels[band], value))
    }

    func setPreamp(_ value: Float) {
        guard preamp != value else { return }
        preamp = value
        eq_set_preamp(engine, value)
        markCustom()
        flash(String(format: "PREAMP  %+.1f DB", value))
    }

    func apply(_ preset: Preset) {
        gains = preset.gains
        preamp = preset.preamp
        presetName = preset.name
        pushToEngine()
        save()
        flash("PRESET: \(preset.name.uppercased())")
    }

    var isProcessing: Bool { tap.isRunning }

    /// Puts back a saved state without the on-screen ticker (used by the self-test).
    func restore(gains: [Float], preamp: Float, presetName: String, enabled: Bool) {
        self.gains = gains
        self.preamp = preamp
        self.presetName = presetName
        pushToEngine()
        save()
        if enabled != self.enabled { setEnabled(enabled) }
    }

    func shutdown() {
        tap.stop()
        save()
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            flash("LOGIN ITEM: \(error.localizedDescription.uppercased())")
        }
        objectWillChange.send()
    }

    // MARK: Private

    private func startAudio() {
        do {
            try tap.start()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshOutputName()
    }

    private func outputDeviceChanged() {
        refreshOutputName()
        if enabled { startAudio() }
    }

    private func refreshOutputName() {
        outputName = (try? AudioDevices.defaultOutput()).map(AudioDevices.name) ?? "No output"
    }

    private func markCustom() {
        presetName = "Custom"
        save()
    }

    private func flash(_ text: String) {
        ticker = text
        tickerClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.ticker = nil }
        tickerClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func pushToEngine() {
        for (i, g) in gains.enumerated() { eq_set_band_gain(engine, Int32(i), g) }
        eq_set_preamp(engine, preamp)
    }

    private func load() {
        if let saved = defaults.array(forKey: "gains") as? [Double], saved.count == gains.count {
            gains = saved.map(Float.init)
            preamp = defaults.float(forKey: "preamp")
            presetName = defaults.string(forKey: "preset") ?? "Custom"
            enabled = defaults.bool(forKey: "enabled")
        } else {
            // First launch: start with bass boosted.
            let preset = Preset.all.first { $0.name == "Bass Boost" } ?? .flat
            gains = preset.gains
            preamp = preset.preamp
            presetName = preset.name
            enabled = true
            if !snapshotMode { defaults.set(true, forKey: "enabled") }
            save()
        }
    }

    private func save() {
        guard !snapshotMode else { return }
        defaults.set(gains.map(Double.init), forKey: "gains")
        defaults.set(preamp, forKey: "preamp")
        defaults.set(presetName, forKey: "preset")
    }
}

/// Polls the engine's output peaks for the LCD level meter.
final class LevelMeter: ObservableObject {
    @Published private(set) var left: Float = 0
    @Published private(set) var right: Float = 0
    private var timer: Timer?

    init(model: EQModel) {
        let engine = model.engine
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak model] _ in
            guard let self else { return }
            var l: Float = 0, r: Float = 0
            eq_read_peaks(engine, &l, &r)
            if model?.enabled != true { l = 0; r = 0 }
            let nl = Self.normalize(l), nr = Self.normalize(r)
            let newL = max(nl, self.left - 0.04), newR = max(nr, self.right - 0.04)
            if newL != self.left || newR != self.right {
                self.left = newL
                self.right = newR
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Maps -48...0 dBFS to 0...1.
    private static func normalize(_ peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(peak)
        return min(max((db + 48) / 48, 0), 1)
    }
}
