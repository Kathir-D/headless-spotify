#!/bin/sh
# MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
#
# check-icon.sh — assert the built app's icon is the icon we think it is.
#
# Every other check in this repo inspects files. This one renders the icon the
# way macOS does and looks at the result, because the failure it exists to catch
# is invisible in the file: a malformed AppIcon.icns still passes `iconutil`,
# still round-trips through `iconutil -c iconset`, and still passes
# `codesign --verify`, while the Dock shows a grey plate instead of the artwork.
#
# What is asserted, and why each one:
#
#   1. AppIcon.icns exists and CFBundleIconFile names it. A bundle with no icon
#      gets the generic document glyph, silently.
#   2. The icns round-trips through iconutil, so it is not a file iconutil
#      happens to tolerate.
#   3. The rendered icon is the *artwork*, not macOS's fallback plate. The
#      fallback is a flat neutral grey rounded rect; the artwork has the blue
#      end of the ramp in its top-left quadrant. Comparing those two specific
#      pixels is what makes this a real assertion instead of a smoke test.
#   4. The mark is present, i.e. the disc is not empty. A missing SF Symbol or a
#      dropped clip leaves a clean gradient and no mark.
#   5. There is no 1024x1024 representation. See the long comment on
#      iconsetSizes in scripts/make-icon.swift: with one present, IconServices
#      masks the icon a second time and the user gets a grey plate.
#
# The rendered icon comes from NSWorkspace.icon(forFile:), which is the same
# path LaunchServices and the Dock use. Reading the PNG out of the bundle would
# bypass the very thing being tested.
#
# Usage: ./scripts/check-icon.sh <path/to/headless-spotify.app>
set -eu

APP="${1:?usage: check-icon.sh <path/to/headless-spotify.app>}"
ICNS="$APP/Contents/Resources/AppIcon.icns"
PLIST="$APP/Contents/Info.plist"

fail() { echo "error: $1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. The icon is there and the plist points at it.
[ -s "$ICNS" ] || fail "$ICNS is missing or empty"
KEY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST" 2>/dev/null || true)"
[ "$KEY" = "AppIcon" ] || fail "CFBundleIconFile is '$KEY', expected 'AppIcon'"

# 2. It is a real icns.
iconutil -c iconset "$ICNS" -o "$TMP/roundtrip.iconset" >/dev/null 2>&1 \
  || fail "iconutil could not read $ICNS"
COUNT="$(ls -1 "$TMP/roundtrip.iconset" | wc -l | tr -d ' ')"
[ "$COUNT" -ge 9 ] || fail "the icns round-tripped to only $COUNT representations, expected at least 9"

# IconServices caches an app's icon by bundle identifier, so asking it about
# com.headless-spotify.bar returns whatever it decided the *previous* build of
# that identifier looked like. The check would then pass or fail according to
# what was installed an hour ago, which is worse than no check at all.
#
# So render a copy under an identifier nothing has ever used. The copy is
# byte-identical apart from that one string.
PROBE="$TMP/IconProbe.app"
cp -R "$APP" "$PROBE"
PROBE_ID="com.headless-spotify.icontest.$$.$(date +%s)"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PROBE_ID" "$PROBE/Contents/Info.plist" >/dev/null 2>&1 \
  || fail "could not set a unique bundle identifier on the probe copy"
# Re-signing is not needed for NSWorkspace to read the icon, and the seal is
# checked separately by scripts/package-release.sh.
APP="$PROBE"

# 3 + 4 + 5, on the rendered pixels.
cat > "$TMP/render.swift" <<'SWIFT'
import AppKit
import Foundation

let appPath = CommandLine.arguments[1]
let iconset = CommandLine.arguments[2]
let outPath = CommandLine.arguments[3]

// A 1024 representation makes IconServices mask the artwork a second time and
// render a grey plate. Caught here rather than by inspecting the file, because
// the file looks fine.
if FileManager.default.fileExists(atPath: iconset + "/icon_512x512@2x.png") {
    FileHandle.standardError.write(Data("icon: the icns carries a 1024x1024 representation\n".utf8))
    exit(3)
}

let icon = NSWorkspace.shared.icon(forFile: appPath)
guard let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon: could not render the app icon\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

swiftc -O -o "$TMP/render" "$TMP/render.swift" >/dev/null 2>&1 \
  || fail "could not build the icon renderer"
# `if ! cmd` would clobber $?, so the status is captured first and the specific
# reason for a non-zero exit is reported rather than a generic failure.
set +e
"$TMP/render" "$APP" "$TMP/roundtrip.iconset" "$TMP/rendered.png"
RENDER_STATUS=$?
set -e
if [ "$RENDER_STATUS" -eq 3 ]; then
  fail "the icns carries a 1024x1024 representation; IconServices masks the artwork a second time and the Dock shows a grey plate (see scripts/make-icon.swift)"
fi
[ "$RENDER_STATUS" -eq 0 ] || fail "the icon could not be rendered (renderer exit $RENDER_STATUS)"
[ -s "$TMP/rendered.png" ] || fail "the renderer produced no image"

# Read the rendered pixels back with sips/PlistBuddy-free tooling: a tiny
# Swift pass, because the alternative is depending on Python or ImageMagick
# being installed on a build machine.
cat > "$TMP/probe.swift" <<'SWIFT'
import AppKit
import Foundation

let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let width = rep.pixelsWide, height = rep.pixelsHigh
// Sample in the 1024 authoring space, whatever size we were handed.
func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    guard let c = rep.colorAt(x: x * width / 1024, y: y * height / 1024) else { return (0, 0, 0) }
    return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}
func show(_ label: String, _ p: (Int, Int, Int)) { print("\(label)=\(p.0),\(p.1),\(p.2)") }

// The disc is centred at (512, 512) with radius 330. The ramp's extremes are
// found by searching it rather than sampling fixed points: the most-blue and
// most-pink pixels inside the disc are the ramp's two ends wherever the disc
// happens to be, so this does not encode the artwork's exact geometry and
// cannot drift when the disc is resized.
//
// Only opaque pixels count. A transparent one reads back as (0,0,0), which is
// both "bluer than blue" and "pinker than pink", and would win both searches.
var mostBlue = (Int.min, 0, 0, 0)
var mostPink = (Int.max, 0, 0, 0)
var brightest = (0, 0, 0)
for y in stride(from: 182, through: 842, by: 2) {
    for x in stride(from: 182, through: 842, by: 2) {
        let dx = x - 512, dy = y - 512
        if dx * dx + dy * dy > 330 * 330 { continue }
        guard let colour = rep.colorAt(x: x * width / 1024, y: y * height / 1024),
              colour.alphaComponent > 0.9 else { continue }
        let p = (Int(colour.redComponent * 255), Int(colour.greenComponent * 255), Int(colour.blueComponent * 255))
        let blueness = p.2 - p.0
        if blueness > mostBlue.0 { mostBlue = (blueness, p.0, p.1, p.2) }
        if blueness < mostPink.0 { mostPink = (blueness, p.0, p.1, p.2) }
        if p.0 + p.1 + p.2 > brightest.0 + brightest.1 + brightest.2 { brightest = p }
    }
}
show("blueend", (mostBlue.1, mostBlue.2, mostBlue.3))
show("pinkend", (mostPink.1, mostPink.2, mostPink.3))
show("mark", brightest)
// Plate above the disc, still inside the squircle.
show("plate", at(512, 130))
SWIFT
swiftc -O -o "$TMP/probe" "$TMP/probe.swift" >/dev/null 2>&1 \
  || fail "could not build the pixel probe"
SAMPLES="$("$TMP/probe" "$TMP/rendered.png")"
value() { echo "$SAMPLES" | sed -n "s/^$1=\(.*\)$/\1/p"; }

blue_end="$(value blueend)"
pink_end="$(value pinkend)"
mark="$(value mark)"
plate="$(value plate)"

# The fallback plate is neutral grey: r == g == b. The artwork never is, because
# the ramp runs blue to pink. Comparing the channels is what separates "macOS
# drew the icon" from "macOS drew a placeholder".
is_neutral() {
  r="${1%%,*}"; rest="${1#*,}"; g="${rest%%,*}"; b="${rest##*,}"
  [ "$r" -eq "$g" ] && [ "$g" -eq "$b" ]
}
if is_neutral "$blue_end" || is_neutral "$pink_end"; then
  fail "the rendered icon is a neutral grey plate, not the artwork (blue=$blue_end pink=$pink_end) — IconServices rejected the icns"
fi

# The two ends of the ramp, as hexes in scripts/make-icon.swift. The probe
# searched the disc for its most-blue and most-pink pixels, which land on the
# ramp's ends where it meets the disc's edge on the diagonal.
close_to() {
  got="${1%%,*}"; rest="${1#*,}"; g="${rest%%,*}"; b="${rest##*,}"
  for pair in "$got:$2" "$g:$3" "$b:$4"; do
    actual="${pair%%:*}"; want="${pair##*:}"
    diff=$((actual - want)); [ "$diff" -lt 0 ] && diff=$((-diff))
    [ "$diff" -le 40 ] || return 1
  done
}
close_to "$blue_end" 0x5B 0xCE 0xFA || fail "the disc's blue end is $blue_end, expected near #5BCEFA"
close_to "$pink_end" 0xF5 0xA9 0xB8 || fail "the disc's pink end is $pink_end, expected near #F5A9B8"

# The mark is white on a coloured disc, so it must be markedly brighter than
# either ramp end. Without this, a dropped clip or a missing SF Symbol still
# passes every check above and ships a bare gradient.
bright() {
  r="${1%%,*}"; rest="${1#*,}"; g="${rest%%,*}"; b="${rest##*,}"
  echo $(( (r + g + b) / 3 ))
}
[ "$(bright "$mark")" -gt 235 ] || fail "no white mark found inside the disc (brightest was $mark) — the symbol is missing or the disc clip was dropped"
[ "$(bright "$plate")" -gt 235 ] || fail "the plate is not near-white (got $plate)"

echo "ok: the icon renders as the artwork — ramp #5BCEFA→#F5A9B8, white mark, no grey plate"
