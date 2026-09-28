/* MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
 *
 * Accessory-policy injector (fallback when LSUIElement is wiped/ignored).
 * Concept credit: michaelmitchell-bit/hide-macos-app-dock-icon (MIT).
 *
 * Load via DYLD_INSERT_LIBRARIES so this constructor runs before the host's
 * main(): it forces NSApplicationActivationPolicyAccessory (no Dock icon, no
 * Cmd-Tab entry, windows keep working).
 *
 * LIMITS (documented, not hidden):
 *  - Only activates inside com.spotify.client (bundle-ID gate below), so a
 *    leaked DYLD_INSERT_LIBRARIES cannot break your other apps.
 *  - Hardened-runtime binaries (current official Spotify.app) STRIP
 *    DYLD_* env vars at exec, so injection is ignored there and the watcher
 *    keeps the plist mode primary. This dylib is the fallback for
 *    non-hardened builds and future-proofs the design.
 */

#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>

static NSString *const kTargetBundleID = @"com.spotify.client";
static const int kMaxAttempts = 6;          // ~12 s of retries
static const int64_t kRetryDelayNanos = 2 * NSEC_PER_SEC;

static void headless_try_hide(int attempt) {
    @autoreleasepool {
        NSString *host = [[NSBundle mainBundle] bundleIdentifier];
        if (host != nil && ![host isEqualToString:kTargetBundleID]) {
            return; // not our host — never touch other apps
        }
        NSApplication *app = [NSApp respondsToSelector:@selector(activationPolicy)] ? NSApp : nil;
        if (app == nil) {
            app = [NSApplication sharedApplication];
        }
        if (app != nil && [app activationPolicy] != NSApplicationActivationPolicyAccessory) {
            [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }
        if (attempt + 1 < kMaxAttempts) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kRetryDelayNanos),
                           dispatch_get_main_queue(), ^{
                               headless_try_hide(attempt + 1);
                           });
        }
    }
}

__attribute__((constructor)) static void headless_inject(void) {
    @autoreleasepool {
        NSString *host = [[NSBundle mainBundle] bundleIdentifier];
        if (host != nil && ![host isEqualToString:kTargetBundleID]) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            headless_try_hide(0);
        });
    }
}
