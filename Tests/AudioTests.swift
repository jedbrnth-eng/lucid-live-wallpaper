// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Audio analyser, smoothing, reactive look mapping and the Wallpaper Engine web audio shim.
// Synthetic buffers only: no audio device is touched.
import Foundation

private func sine(_ hz: Double, amp: Float = 1, n: Int = 4096, rate: Double = 48_000) -> [Float] {
    (0..<n).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
}
private func argmax(_ a: [Float]) -> Int { a.indices.max { a[$0] < a[$1] } ?? -1 }

func registerAudioTests() {
    test("Audio: 80 Hz sine reads as bass") {
        let f = AudioAnalyser(sampleRate: 48_000).analyse(left: sine(80), right: sine(80))
        expect(f.bass > 0.8, "bass \(f.bass)")
        expect(f.bass > f.mid + 0.4, "bass \(f.bass) mid \(f.mid)")
        expect(f.bass > f.treble + 0.6, "bass \(f.bass) treble \(f.treble)")
    }
    test("Audio: 1 kHz sine reads as mid") {
        let f = AudioAnalyser(sampleRate: 48_000).analyse(left: sine(1000), right: sine(1000))
        expect(f.mid > f.bass + 0.2 && f.mid > f.treble + 0.2, "bass \(f.bass) mid \(f.mid) treble \(f.treble)")
    }
    test("Audio: 8 kHz sine reads as treble") {
        let f = AudioAnalyser(sampleRate: 48_000).analyse(left: sine(8000), right: sine(8000))
        expect(f.treble > f.bass + 0.4 && f.treble > f.mid + 0.2, "bass \(f.bass) mid \(f.mid) treble \(f.treble)")
    }
    test("Audio: spectrum peak band rises with frequency (64 bands)") {
        let a = AudioAnalyser(sampleRate: 48_000)
        let p = [60.0, 250, 1000, 4000, 12000].map { argmax(a.analyse(left: sine($0), right: nil).spectrum) }
        expectEqual(a.analyse(left: sine(440), right: nil).spectrum.count, 64)
        expect(zip(p, p.dropFirst()).allSatisfy { $0 < $1 }, "peak bands \(p)")
    }
    test("Audio: silence is all zeros") {
        let f = AudioAnalyser(sampleRate: 48_000).analyse(left: [Float](repeating: 0, count: 4096), right: [Float](repeating: 0, count: 4096))
        expectEqual(f.level, 0); expectEqual(f.bass, 0); expectEqual(f.mid, 0); expectEqual(f.treble, 0)
        expect(f.weArray.allSatisfy { $0 == 0 })
    }
    test("Audio: Wallpaper Engine array is 128 floats, left then right") {
        let f = AudioAnalyser(sampleRate: 48_000).analyse(left: sine(500), right: [Float](repeating: 0, count: 4096))
        expectEqual(f.weArray.count, 128)
        expect(f.weArray[0..<64].max()! > 0.5, "left half carries the tone")
        expect(f.weArray[64..<128].allSatisfy { $0 == 0 }, "right half silent")
    }
    test("Audio: all values clamped to 0...1 even when overdriven") {
        let f = AudioAnalyser(sampleRate: 48_000).analyse(left: sine(100, amp: 4), right: sine(3000, amp: 4), gain: 8)
        let all = f.weArray + f.spectrum + [f.bass, f.mid, f.treble, f.level]
        expect(all.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
    }
    test("Audio: sensitivity (gain) raises quiet signals") {
        let a = AudioAnalyser(sampleRate: 48_000)
        let quiet = a.analyse(left: sine(200, amp: 0.01), right: nil, gain: 1)
        let boosted = a.analyse(left: sine(200, amp: 0.01), right: nil, gain: 4)
        expect(boosted.level > quiet.level && boosted.bass > quiet.bass, "quiet \(quiet.level)/\(quiet.bass) boosted \(boosted.level)/\(boosted.bass)")
    }
    test("Audio: short and NaN buffers are safe") {
        let a = AudioAnalyser(sampleRate: 44_100)
        let f = a.analyse(left: [0.5, .nan, -0.5], right: nil)
        expect((f.weArray + [f.level]).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        expectEqual(a.analyse(left: [], right: nil).spectrum.count, 64)
    }
    test("Audio: deinterleave splits L/R and handles mono") {
        let (l, r) = AudioBuffers.deinterleave([1, -1, 2, -2, 3, -3], channels: 2)
        expectEqual(l, [1, 2, 3]); expectEqual(r, [-1, -2, -3])
        let (m, n) = AudioBuffers.deinterleave([1, 2, 3], channels: 1)
        expectEqual(m, [1, 2, 3]); expectEqual(n, nil)
    }
    test("Audio: rolling window keeps the newest N samples") {
        var w = RollingWindow(size: 4)
        w.append([1, 2, 3]); expectEqual(w.samples, [0, 1, 2, 3])
        w.append([4, 5, 6]); expectEqual(w.samples, [3, 4, 5, 6])
        w.append([7, 8, 9, 10, 11]); expectEqual(w.samples, [8, 9, 10, 11])
    }
    test("Audio: smoother attacks fast and decays slowly to zero") {
        var s = AudioSmoother(attack: 0.6, release: 0.15)
        let loud = AudioFrame(bass: 1, mid: 1, treble: 1, level: 1, spectrum: .init(repeating: 1, count: 64), left: .init(repeating: 1, count: 64), right: .init(repeating: 1, count: 64))
        let a = s.push(loud)
        expect(a.bass >= 0.6, "attack \(a.bass)")
        var prev = s.push(loud).bass
        var levels: [Float] = []
        for _ in 0..<60 { let v = s.push(.silent).bass; levels.append(v); expect(v <= prev); prev = v }
        expect(levels[0] > 0.5, "decays slowly: \(levels[0])")
        expect(levels.last! < 0.01, "reaches ~0: \(levels.last!)")
    }
    test("Reactive: mapping is identity when off or silent, bounded when loud") {
        let off = ReactiveMapper.look(.silent, options: ReactiveOptions())
        expectEqual(off.scale, 1); expectEqual(off.glow, 0); expectEqual(off.bars.count, 0)
        let loud = AudioFrame(bass: 1, mid: 1, treble: 1, level: 1, spectrum: .init(repeating: 1, count: 64), left: [], right: [])
        let none = ReactiveMapper.look(loud, options: ReactiveOptions())
        expectEqual(none.scale, 1, "no option enabled, no change")
        let on = ReactiveMapper.look(loud, options: ReactiveOptions(pulse: true, glow: true, bars: true))
        expect(on.scale > 1 && on.scale <= 1 + ReactiveMapper.maxZoom + 1e-6, "scale \(on.scale)")
        expect(on.glow > 0 && on.glow <= ReactiveMapper.maxGlow + 1e-6, "glow \(on.glow)")
        expectEqual(on.bars.count, 64)
        let quiet = ReactiveMapper.look(.silent, options: ReactiveOptions(pulse: true, glow: true, bars: true))
        expectEqual(quiet.scale, 1); expectEqual(quiet.glow, 0)
        expect(!ReactiveOptions().any && ReactiveOptions(bars: true).any)
    }
    test("WE shim: defines the audio listener API and passes default properties") {
        let js = WEShim.bootstrapScript(userPropertiesJSON: #"{"customint":{"value":20}}"#)
        for name in ["wallpaperRegisterAudioListener", "wallpaperPropertyListener", "applyUserProperties", "applyGeneralProperties",
                     "wallpaperRegisterMediaStatusListener", "__lucidAudio", "__lucidSetPaused", #"{"customint":{"value":20}}"#] {
            expect(js.contains(name), "missing \(name)")
        }
        expect(!WEShim.bootstrapScript(userPropertiesJSON: "not json </script>").contains("</script>"), "invalid property JSON is dropped")
    }
    test("WE shim: audio call is a 128-number array, NaN and range safe") {
        var a = [Float](repeating: 0.5, count: 128); a[3] = .nan; a[4] = 7; a[5] = -1
        let call = WEShim.audioCall(a)
        expect(call.hasPrefix("window.__lucidAudio&&window.__lucidAudio(["), call)
        let inner = call.drop { $0 != "[" }.dropFirst().prefix { $0 != "]" }
        let nums = inner.split(separator: ",").compactMap { Double($0) }
        expectEqual(nums.count, 128)
        expectEqual(nums[3], 0); expectEqual(nums[4], 1); expectEqual(nums[5], 0)
        expectEqual(WEShim.audioCall([0.25]).filter { $0 == "," }.count, 127, "short arrays are padded to 128")
    }
}
