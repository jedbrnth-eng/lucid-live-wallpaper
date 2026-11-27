// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Keeps the power reading (on battery or not, and the charge) current without polling. macOS pushes power-source
// changes through a run-loop source (IOPSNotificationCreateRunLoopSource in the app), and the reading is taken
// again whenever the Mac or its displays wake, because plugging in or unplugging during sleep may send no event.
// The source reaches the monitor through a retained box that holds it weakly, so a late callback can never touch
// freed memory, and the source is invalidated (taken off every run loop) when the monitor goes away. It runs in
// the common modes, so a change still arrives while a menu or slider is tracking. Foundation only, unit-tested.
import Foundation

final class PowerMonitor {
    typealias SourceFactory = (UnsafeMutableRawPointer) -> CFRunLoopSource?
    private final class Box { weak var monitor: PowerMonitor? }

    /// The C callback every source must use, with the context the factory is given.
    static let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
        guard let ctx else { return }
        Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue().monitor?.update()
    }

    private(set) var source: CFRunLoopSource?
    private(set) var last: PowerReading?
    private let box: Unmanaged<Box>
    private let read: () -> PowerReading?
    private let onChange: (PowerReading) -> Void
    private var observers: [NSObjectProtocol] = []
    private weak var center: NotificationCenter?

    init(read: @escaping () -> PowerReading?, wakeCenter: NotificationCenter, wakeNames: [Notification.Name],
         makeSource: SourceFactory?, onChange: @escaping (PowerReading) -> Void) {
        self.read = read
        self.onChange = onChange
        let b = Box()
        box = Unmanaged.passRetained(b)
        center = wakeCenter
        b.monitor = self
        if let s = makeSource?(box.toOpaque()) {
            source = s
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        }
        observers = wakeNames.map { wakeCenter.addObserver(forName: $0, object: nil, queue: nil) { [weak self] _ in self?.update() } }
        update()
    }

    deinit {
        if let s = source { CFRunLoopSourceInvalidate(s) }
        observers.forEach { center?.removeObserver($0) }
        box.release()
    }

    /// Reads the power source and reports it if it changed.
    func update() {
        guard let r = read(), r != last else { return }
        last = r
        onChange(r)
    }
}
