/* MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
 *
 * Public header for the accessory-policy injector dylib. The dylib acts
 * purely through its constructor (no API to call); this header exists to
 * satisfy the package manager's C-target layout.
 */
#ifndef HEADLESS_INJECTOR_H
#define HEADLESS_INJECTOR_H

/* Target host bundle gated inside injector.c. */
#define HEADLESS_SPOTIFY_TARGET_BUNDLE_ID "com.spotify.client"

#endif /* HEADLESS_INJECTOR_H */
