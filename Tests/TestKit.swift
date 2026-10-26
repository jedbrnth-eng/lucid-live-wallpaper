// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// A tiny dependency-free test runner (the app is built with swiftc, not Xcode, so there is no XCTest target).
import Foundation

nonisolated(unsafe) var registeredTests: [(name: String, body: () throws -> Void)] = []
nonisolated(unsafe) var currentFailures: [String] = []

func test(_ name: String, _ body: @escaping () throws -> Void) { registeredTests.append((name, body)) }

func expect(_ cond: Bool, _ msg: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !cond { currentFailures.append("\(file):\(line) expectation failed. \(msg())") }
}
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if a != b { currentFailures.append("\(file):\(line) expected \(b), got \(a). \(msg())") }
}
func expectNear(_ a: Double, _ b: Double, _ tol: Double, _ msg: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !(abs(a - b) <= tol) { currentFailures.append("\(file):\(line) expected \(b) ± \(tol), got \(a). \(msg())") }
}

/// Runs every registered test (optionally only names containing `filter`) and returns the process exit code.
func runAllTests(filter: String?) -> Int32 {
    var passed = 0, failed = 0
    for t in registeredTests where filter.map({ t.name.contains($0) }) ?? true {
        currentFailures = []
        do { try t.body() } catch { currentFailures.append("threw: \(error)") }
        if currentFailures.isEmpty { passed += 1; print("PASS  \(t.name)") }
        else { failed += 1; print("FAIL  \(t.name)"); currentFailures.forEach { print("      \($0)") } }
    }
    print("\nTest summary: \(passed + failed) tests, \(passed) passed, \(failed) failed")
    return failed == 0 && passed > 0 ? 0 : 1
}
