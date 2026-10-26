// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Test entry point: ./test.sh [name-filter]
import Foundation

registerWallpaperEngineImportTests()
registerAudioTests()
registerDayNightTests()
registerModelCompatTests()
setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments.dropFirst().first
exit(runAllTests(filter: args))
