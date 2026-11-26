// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Watches one process from the outside for headless-check.sh: every 50 ms it asks the window server which windows
// that process has on screen (any level, the desktop level included), until the process exits. It also compares
// every display's desktop picture before and after. Exit 0 only if no window was ever on screen and no desktop
// picture changed. It only looks: a process still running after the time limit is reported (timed_out=yes) and
// left to the caller, which owns it.
// Usage: window-watch <pid> [seconds]
#import <AppKit/AppKit.h>
#include <sys/sysctl.h>

static BOOL alive(pid_t pid) {
    struct kinfo_proc kp;
    size_t len = sizeof kp;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0) return NO;
    return kp.kp_proc.p_stat != SZOMB;
}

static NSDictionary *desktopPictures(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSScreen *s in [NSScreen screens]) {
        NSString *key = [s.deviceDescription[@"NSScreenNumber"] description] ?: @"?";
        d[key] = [[NSWorkspace sharedWorkspace] desktopImageURLForScreen:s].path ?: @"(none)";
    }
    return d;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: window-watch <pid> [seconds]\n"); return 2; }
        pid_t pid = (pid_t)atoi(argv[1]);
        double limit = argc > 2 ? atof(argv[2]) : 300;
        NSDictionary *before = desktopPictures();
        NSMutableSet *seen = [NSMutableSet set];
        NSDate *start = [NSDate date];
        long polls = 0;
        int most = 0;
        BOOL timedOut = NO;
        while (alive(pid)) {
            if (-[start timeIntervalSinceNow] > limit) { timedOut = YES; break; }
            CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
            int on = 0;
            for (NSDictionary *w in (__bridge NSArray *)list) {
                if ([w[(id)kCGWindowOwnerPID] intValue] != pid) continue;
                on++;
                NSNumber *number = w[(id)kCGWindowNumber];
                if (![seen containsObject:number]) {
                    [seen addObject:number];
                    NSDictionary *b = w[(id)kCGWindowBounds];
                    printf("ONSCREEN at %.1f s: window %s layer %s %sx%s at (%s, %s)\n", -[start timeIntervalSinceNow],
                           number.description.UTF8String, [w[(id)kCGWindowLayer] description].UTF8String,
                           [b[@"Width"] description].UTF8String, [b[@"Height"] description].UTF8String,
                           [b[@"X"] description].UTF8String, [b[@"Y"] description].UTF8String);
                }
            }
            if (list) CFRelease(list);
            if (on > most) most = on;
            polls++;
            usleep(50000);
        }
        BOOL changed = ![before isEqualToDictionary:desktopPictures()];
        printf("polls=%ld seconds=%.1f max_onscreen=%d windows_seen=%lu desktop_picture_changed=%s timed_out=%s\n", polls,
               -[start timeIntervalSinceNow], most, (unsigned long)seen.count, changed ? "yes" : "no", timedOut ? "yes" : "no");
        return (most == 0 && !changed && !timedOut) ? 0 : 1;
    }
}
