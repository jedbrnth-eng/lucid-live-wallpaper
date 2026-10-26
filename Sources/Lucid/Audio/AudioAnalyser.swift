// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Audio analyser: turns raw system-audio samples into band levels (bass/mid/treble), an overall level
// and a 64-band spectrum per channel (the 128-float layout Wallpaper Engine web wallpapers expect).
// Pure and synchronous (no audio device, no threads), so it is unit-tested with synthetic sine waves.
import Foundation
import Accelerate

struct AudioFrame: Equatable {
    var bass: Float, mid: Float, treble: Float, level: Float
    var spectrum: [Float]          // 64 bands, max of left/right, 0...1
    var left: [Float], right: [Float]   // 64 bands each, 0...1
    static let silent = AudioFrame(bass: 0, mid: 0, treble: 0, level: 0, spectrum: [], left: [], right: [])
    static let bands = 64

    /// Wallpaper Engine's `wallpaperRegisterAudioListener` layout: 64 left bands (bass→treble), then 64 right bands.
    var weArray: [Float] { AudioFrame.pad(left) + AudioFrame.pad(right) }
    static func pad(_ a: [Float]) -> [Float] { a.count >= bands ? Array(a.prefix(bands)) : a + [Float](repeating: 0, count: bands - a.count) }
}

final class AudioAnalyser {
    let sampleRate: Double
    let fftSize: Int
    static let minHz = 30.0, maxHz = 16_000.0
    static let bassTop = 250.0, midTop = 4_000.0
    /// Levels are mapped from dBFS: `floorDB` and below -> 0, 0 dBFS (a full-scale sine) -> 1.
    static let floorDB: Float = -60

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let windowSum: Float
    private let bandBins: [ClosedRange<Int>]
    private let bassBins: ClosedRange<Int>, midBins: ClosedRange<Int>, trebleBins: ClosedRange<Int>

    init(sampleRate: Double, fftSize: Int = 2048) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        var n = 64
        while n < fftSize { n *= 2 }
        self.fftSize = n
        log2n = vDSP_Length(log2(Double(n)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        windowSum = vDSP.sum(window)
        let binHz = self.sampleRate / Double(n), lastBin = n / 2 - 1
        func bin(_ hz: Double) -> Int { min(lastBin, max(1, Int((hz / binHz).rounded()))) }
        let top = min(Self.maxHz, self.sampleRate / 2 * 0.95)
        let edges = (0...AudioFrame.bands).map { Self.minHz * pow(top / Self.minHz, Double($0) / Double(AudioFrame.bands)) }
        bandBins = (0..<AudioFrame.bands).map { i in let lo = bin(edges[i]); return lo...max(lo, bin(edges[i + 1]) - 1) }
        bassBins = bin(20)...max(bin(20), bin(Self.bassTop) - 1)
        midBins = bin(Self.bassTop)...max(bin(Self.bassTop), bin(Self.midTop) - 1)
        trebleBins = bin(Self.midTop)...max(bin(Self.midTop), bin(top))
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    /// Single-sided amplitude spectrum (n/2 bins): a sine of amplitude A centred on a bin reads A.
    func amplitudes(_ samples: [Float]) -> [Float] {
        let n = fftSize, half = n / 2
        var x = [Float](repeating: 0, count: n)
        let src = samples.suffix(n)
        var i = n - src.count
        for s in src { x[i] = s.isFinite ? s : 0; i += 1 }
        vDSP.multiply(x, window, result: &x)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        // vDSP's real FFT is scaled by 2; single-sided amplitude = 2|X| / sum(window) = |zrip| / sum(window).
        let scale = windowSum > 0 ? 1 / windowSum : 0
        mags = vDSP.multiply(scale, mags)
        mags[0] = 0   // packed DC/Nyquist, not useful for visuals
        return mags
    }

    static func unit(_ amplitude: Float, gain: Float) -> Float {
        let a = amplitude * max(0, gain)
        guard a.isFinite, a > 1e-9 else { return a.isFinite ? 0 : 1 }
        let db = 20 * log10(a)
        return min(1, max(0, (db - floorDB) / -floorDB))
    }

    private func energy(_ amps: [Float], _ r: ClosedRange<Int>) -> Float {
        var s: Float = 0
        for k in r where k < amps.count { s += amps[k] * amps[k] }
        return s.squareRoot()
    }

    private func bands(_ amps: [Float], gain: Float) -> [Float] {
        bandBins.map { r in Self.unit(r.lazy.filter { $0 < amps.count }.map { amps[$0] }.max() ?? 0, gain: gain) }
    }

    /// `gain` is the user's sensitivity (1 = neutral). `right == nil` means mono: both channels get the same data.
    func analyse(left: [Float], right: [Float]?, gain: Float = 1) -> AudioFrame {
        let la = amplitudes(left)
        let ra = right.map(amplitudes) ?? la
        let lb = bands(la, gain: gain), rb = right == nil ? lb : bands(ra, gain: gain)
        let spectrum = zip(lb, rb).map { max($0, $1) }
        func range(_ r: ClosedRange<Int>) -> Float { Self.unit(max(energy(la, r), energy(ra, r)), gain: gain) }
        func rms(_ s: [Float]) -> Float {
            let t = s.suffix(fftSize).map { $0.isFinite ? $0 : 0 }
            guard !t.isEmpty else { return 0 }
            return (t.reduce(0) { $0 + $1 * $1 } / Float(t.count)).squareRoot()
        }
        // RMS × √2 so a full-scale sine reads 0 dBFS, like the band amplitudes.
        let level = Self.unit(max(rms(left), rms(right ?? left)) * 2.0.squareRoot().f, gain: gain)
        return AudioFrame(bass: range(bassBins), mid: range(midBins), treble: range(trebleBins), level: level,
                          spectrum: spectrum, left: lb, right: rb)
    }
}

private extension Double { var f: Float { Float(self) } }

enum AudioBuffers {
    /// Interleaved [L0, R0, L1, R1, …] -> (left, right). Mono input returns `right == nil`; extra channels are ignored.
    static func deinterleave(_ x: [Float], channels: Int) -> ([Float], [Float]?) {
        guard channels > 1 else { return (x, nil) }
        let frames = x.count / channels
        var l = [Float](repeating: 0, count: frames), r = [Float](repeating: 0, count: frames)
        for i in 0..<frames { l[i] = x[i * channels]; r[i] = x[i * channels + 1] }
        return (l, r)
    }
}

/// Keeps the newest `size` samples (zero-filled at start) so every analysis sees a full FFT window.
struct RollingWindow {
    private(set) var samples: [Float]
    init(size: Int) { samples = [Float](repeating: 0, count: max(1, size)) }
    mutating func append(_ x: [Float]) {
        let n = samples.count
        if x.count >= n { samples = Array(x.suffix(n)); return }
        samples.removeFirst(x.count)
        samples.append(contentsOf: x)
    }
}

/// Fast attack, slow release, so visuals punch on a beat and fall back smoothly.
struct AudioSmoother {
    var attack: Float, release: Float
    private var state = AudioFrame.silent
    init(attack: Float, release: Float) { self.attack = attack; self.release = release }
    private func step(_ v: Float, _ t: Float) -> Float { v + (t - v) * (t > v ? attack : release) }
    private func step(_ v: [Float], _ t: [Float]) -> [Float] {
        let n = max(v.count, t.count)
        return (0..<n).map { step($0 < v.count ? v[$0] : 0, $0 < t.count ? t[$0] : 0) }
    }
    mutating func push(_ f: AudioFrame) -> AudioFrame {
        state = AudioFrame(bass: step(state.bass, f.bass), mid: step(state.mid, f.mid), treble: step(state.treble, f.treble),
                           level: step(state.level, f.level), spectrum: step(state.spectrum, f.spectrum),
                           left: step(state.left, f.left), right: step(state.right, f.right))
        return state
    }
    mutating func reset() { state = .silent }
}
