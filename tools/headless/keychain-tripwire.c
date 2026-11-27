// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Keychain tripwire for headless-check.sh. Loaded into a development run with DYLD_INSERT_LIBRARIES, it takes the
// place of the Keychain calls Lucid can make (dyld interposing): each one is written to $LUCID_TRIPWIRE_LOG and
// answered with "not found", so a run with this library loaded never reads the real Keychain and macOS never asks
// for access, even when the check under test is broken. Build: clang -dynamiclib -framework Security ...
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void note(const char *what) {
    const char *path = getenv("LUCID_TRIPWIRE_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s pid=%d\n", what, (int)getpid());
    fclose(f);
}

__attribute__((constructor)) static void loaded(void) { note("loaded"); }

static OSStatus tw_copy_matching(CFDictionaryRef query, CFTypeRef *result) {
    note("SecItemCopyMatching");
    if (result) *result = NULL;
    return errSecItemNotFound;
}
static OSStatus tw_add(CFDictionaryRef attributes, CFTypeRef *result) {
    note("SecItemAdd");
    if (result) *result = NULL;
    return errSecNotAvailable;
}
static OSStatus tw_update(CFDictionaryRef query, CFDictionaryRef attributes) {
    note("SecItemUpdate");
    return errSecItemNotFound;
}
static OSStatus tw_delete(CFDictionaryRef query) {
    note("SecItemDelete");
    return errSecItemNotFound;
}

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *r; const void *o; } interpose_##original \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)&replacement, (const void *)&original };

INTERPOSE(tw_copy_matching, SecItemCopyMatching)
INTERPOSE(tw_add, SecItemAdd)
INTERPOSE(tw_update, SecItemUpdate)
INTERPOSE(tw_delete, SecItemDelete)
