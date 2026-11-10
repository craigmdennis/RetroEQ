import AudioToolbox
import CoreAudio
import EQDSP
import Foundation

struct AudioError: LocalizedError {
    let action: String
    let status: OSStatus
    var errorDescription: String? { "Could not \(action) (\(status))" }
}

private func check(_ status: OSStatus, _ action: String) throws {
    if status != noErr { throw AudioError(action: action, status: status) }
}

private func address(_ selector: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

enum AudioDevices {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func defaultOutput() throws -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id), "find the output device")
        if id == kAudioObjectUnknown { throw AudioError(action: "find the output device", status: -1) }
        return id
    }

    static func string(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value), "read device info")
        guard let value else { throw AudioError(action: "read device info", status: -1) }
        return value.takeRetainedValue() as String
    }

    static func uid(_ device: AudioObjectID) throws -> String { try string(device, kAudioDevicePropertyDeviceUID) }
    static func name(_ device: AudioObjectID) -> String { (try? string(device, kAudioObjectPropertyName)) ?? "Output" }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(system, &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj)
        return (err == noErr && obj != kAudioObjectUnknown) ? obj : nil
    }
}

/// Captures all system audio with a muted process tap, runs it through the EQ,
/// and plays it to the current default output device via a private aggregate device.
final class SystemAudioTap {
    private let engine: OpaquePointer
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var pendingChange: DispatchWorkItem?

    /// Called on the main queue when the default output device or its sample rate changes.
    var onDeviceChange: (() -> Void)?

    var isRunning: Bool { procID != nil }

    init(engine: OpaquePointer) {
        self.engine = engine
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioDevices.system, &addr, .main) { [weak self] _, _ in
            self?.scheduleDeviceChange()
        }
    }

    func start() throws {
        stop()
        do { try build() } catch { stop(); throw error }
    }

    func stop() {
        removeRateListener()
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func build() throws {
        let output = try AudioDevices.defaultOutput()
        outputDeviceID = output
        let outputUID = try AudioDevices.uid(output)

        // Exclude ourselves so our own processed output is never fed back into the tap.
        var exclude: [AudioObjectID] = []
        if let me = AudioDevices.processObject(pid: getpid()) { exclude.append(me) }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        description.uuid = UUID()
        description.name = "RetroEQ"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped // originals go silent only while we play them back

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "capture system audio")
        tapID = tap

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "RetroEQ Output",
            kAudioAggregateDeviceUIDKey: "local.RetroEQ.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg), "open the output device")
        aggregateID = agg

        let rate = AudioDevices.nominalSampleRate(agg) ?? AudioDevices.nominalSampleRate(output) ?? 48000
        eq_set_sample_rate(engine, rate)
        eq_request_reset(engine)

        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcID(agg, eq_ioproc, UnsafeMutableRawPointer(engine), &proc), "attach the equalizer")
        procID = proc
        try check(AudioDeviceStart(agg, proc), "start audio")

        addRateListener(on: output)
    }

    private func addRateListener(on device: AudioObjectID) {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleDeviceChange() }
        if AudioObjectAddPropertyListenerBlock(device, &addr, .main, block) == noErr { rateListener = block }
    }

    private func removeRateListener() {
        guard let block = rateListener else { return }
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        AudioObjectRemovePropertyListenerBlock(outputDeviceID, &addr, .main, block)
        rateListener = nil
    }

    private func scheduleDeviceChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onDeviceChange?() }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
