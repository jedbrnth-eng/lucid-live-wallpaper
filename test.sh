#!/bin/bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

# Unit tests for Lucid's pure logic (no window server, audio device or network needed).
# Compiles the UI-free sources listed in Tests/pure-sources.txt together with Tests/*.swift.
# Usage: ./test.sh [name-filter]
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
SOURCES=()
while IFS= read -r f; do [ -n "$f" ] && [ "${f:0:1}" != "#" ] && SOURCES+=("$f"); done < Tests/pure-sources.txt
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Tests -name '*.swift' | sort)
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -framework Accelerate \
  "${SOURCES[@]}" -o build/LucidTests
LUCID_FIXTURES="$PWD/Tests/Fixtures" build/LucidTests "$@"
