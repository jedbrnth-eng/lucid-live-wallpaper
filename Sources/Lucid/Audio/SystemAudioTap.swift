// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// System output audio capture with a Core Audio process tap (macOS 14.2+). Audio-only: no microphone and no
// screen recording. macOS asks once for "System Audio Recording" permission. If it is denied the tap simply
// delivers silence, which the controller reports as "No sound detected".
// Samples stay in memory (a 2048-sample rolling window per channel); nothing is recorded or sent anywhere.
import Foundation
import CoreAudio
import AudioToolbox

enum AudioTapError: LocalizedError {
    case failed(String, OSStatus)
    var errorDescription: String? {
        switch self { case .failed(let what, let s): return "\(what) failed (OSStatus \(s))" }
    }
}

@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.jedbrn.lucid.audio-tap", qos: .userInteractive)
    private let lock = NSLock()
    private var left = RollingWindow(size: 2048), right = RollingWindow(size: 2048)
    private var callbacks = 0
    private(set) var sampleRate: Double = 48_000
    private var isFloat = true, interleaved = false, channels = 2

    private static func check(_ s: OSStatus, _ what: String) throws { if s != noErr { throw AudioTapError.failed(what, s) } }

    private static func property<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        try check(withUnsafeMutableBytes(of: &value) { AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0.baseAddress!) }, "read audio property")
        return value
    }

    private static func string(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try check(withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0) }, "read audio property")
        return (value?.takeRetainedValue() as String?) ?? ""
    }

    func start() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.name = "Lucid audio-reactive wallpapers"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        try Self.check(AudioHardwareCreateProcessTap(desc, &tapID), "Creating the system audio tap")

        let tapUID = try Self.string(tapID, kAudioTapPropertyUID)
        let outputID = try Self.property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, AudioObjectID(kAudioObjectUnknown))
        let outputUID = try Self.string(outputID, kAudioDevicePropertyDeviceUID)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lucid Audio Tap",
            kAudioAggregateDeviceUIDKey: "com.jedbrn.lucid.tap." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
        ]
        try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Creating the capture device")

        let fmt = try Self.property(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        sampleRate = fmt.mSampleRate > 0 ? fmt.mSampleRate : 48_000
        isFloat = fmt.mFormatID == kAudioFormatLinearPCM && (fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && fmt.mBitsPerChannel == 32
        interleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        channels = Int(max(1, fmt.mChannelsPerFrame))

        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.ingest(input)
        }, "Starting audio capture")
        try Self.check(AudioDeviceStart(aggregateID, procID), "Starting audio capture")
    }

    private func ingest(_ input: UnsafePointer<AudioBufferList>) {
        guard isFloat else { return }
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        func floats(_ b: AudioBuffer) -> [Float] {
            guard let p = b.mData else { return [] }
            return Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: Int(b.mDataByteSize) / MemoryLayout<Float>.size))
        }
        var l: [Float] = [], r: [Float]? = nil
        if abl.count >= 2 { l = floats(abl[0]); r = floats(abl[1]) }
        else if let b = abl.first {
            let x = floats(b)
            (l, r) = AudioBuffers.deinterleave(x, channels: interleaved ? Int(max(1, b.mNumberChannels)) : 1)
        }
        lock.lock()
        left.append(l); right.append(r ?? l); callbacks += 1
        lock.unlock()
    }

    /// Newest samples per channel and how many buffers arrived since the last call.
    func snapshot() -> (left: [Float], right: [Float], buffers: Int) {
        lock.lock(); defer { lock.unlock() }
        let n = callbacks; callbacks = 0
        return (left.samples, right.samples, n)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let p = procID { AudioDeviceDestroyIOProcID(aggregateID, p) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }
}
