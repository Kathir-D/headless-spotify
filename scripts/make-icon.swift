#!/usr/bin/env swift
// MIT License — Copyright (c) 2026 headless-spotify Contributors (see LICENSE).
//
// make-icon.swift — render the app icon, and the repo logo, from code.
//
// The icon is not a checked-in binary. It is drawn here on every build, for the
// same reason Info.plist is written by a script: a bitmap nobody can rebuild is
// a bitmap nobody can fix. Changing a colour means changing this file.
//
// The visual language is Sonar's, because the two apps sit side by side in the
// same menu bar and the same Dock and should read as one family:
//
//   * the macOS squircle plate, near-white
//   * a disc filled with a 45° ramp from #5BCEFA to #F5A9B8
//   * a white mark in the middle
//
// Those two colours and that angle are Sonar's, measured off its shipped
// icon-512.png rather than eyeballed. A least-squares fit over the disc's
// interior pixels put the gradient axis on the 45° diagonal (R² 0.91, against
// 0.0006 for the anti-diagonal, so the direction is not in doubt) and
// extrapolated it to (91, 205, 249) at one end and (244, 168, 184) at the other
// — which are #5BCEFA and #F5A9B8 to within a rounding step. The commit that
// introduced Sonar's icon calls the same ramp "radial from the top-left corner";
// across a disc that small the two are visually indistinguishable, and a linear
// ramp is the one that can be written down as two colours and an angle, so that
// is what is written down here.
//
// The mark is the same SF Symbol the menu bar shows when Spotify is visible
// (MenuBarModel.visibleIconSymbolName), so the Dock icon and the top-bar icon
// are one drawing. It is white because both ends of the ramp are light pastels
// and white is the only ink that keeps a single shape readable on them.
//
// Usage:
//   swift scripts/make-icon.swift <output.icns>
//   swift scripts/make-icon.swift --logo <output.png> [--size N]
//   swift scripts/make-icon.swift --preview <output.png> [--size N]

import AppKit
import Foundation

// MARK: - Geometry

/// Everything is authored on the 1024×1024 master canvas that macOS icons are
/// drawn on, and scaled from there, so proportions cannot drift between sizes.
enum Canvas {
    static let master = 1024.0

    /// The plate is 824pt inside the 1024 canvas.
    ///
    /// 824 is Apple's own macOS icon grid, and it is what Sonar uses. Fitting a
    /// superellipse to Sonar's shipped icon put it at 823-824, so this is not a
    /// coincidence to be rounded away: matching it exactly is what makes the
    /// two icons the same size in the Dock, which is the whole reason to share
    /// a colourway in the first place.
    static let plateSize = 824.0

    /// Superellipse exponent. Apple draws the macOS icon shape as
    /// |x/a|^n + |y/a|^n = 1 with n = 5; fitting Sonar's plate put it at 4.9.
    static let plateExponent = 5.0

    /// The gradient disc, and the hairline rim outside it. Both measured off
    /// Sonar in this same 1024 canvas: the disc's saturated interior stops at
    /// r ≈ 330, the rim's outer edge sits at r ≈ 361.
    static let discRadius = 330.0
    static let rimRadius = 361.0
    static let rimWidth = 3.0

    /// The mark's height, as a fraction of the disc's radius.
    ///
    /// 1.0 puts the note at 42% of the disc's diameter. Sonar's arcs measure
    /// 47% by height but 73% by width, because three stacked arcs are wide and
    /// flat; a single note is tall and narrow, so matching Sonar's width would
    /// make it tower over the disc. Height is the proportion that carries across
    /// the change of mark, and at 1.0 the two read as the same weight.
    ///
    /// Overridable only so the value can be swept and re-measured; a build never
    /// sets it, which is what keeps this file the single source of truth.
    static let markScale = Double(ProcessInfo.processInfo.environment["MARK_SCALE"] ?? "") ?? 1.0
}

/// The ramp. See the header for how these values were arrived at.
enum Palette {
    /// #5BCEFA, the top-left end.
    static let rampStart = NSColor(srgbRed: 0x5B / 255.0, green: 0xCE / 255.0, blue: 0xFA / 255.0, alpha: 1)

    /// #F5A9B8, the bottom-right end.
    static let rampEnd = NSColor(srgbRed: 0xF5 / 255.0, green: 0xA9 / 255.0, blue: 0xB8 / 255.0, alpha: 1)

    /// The plate. Sonar's is not flat white — it is a shade cooler at the top
    /// than at the bottom, which is what stops it reading as a hole in the Dock.
    static let plateTop = NSColor(srgbRed: 250 / 255.0, green: 251 / 255.0, blue: 255 / 255.0, alpha: 1)
    static let plateBottom = NSColor.white

    /// The rim, a very light tint near the ramp's midpoint.
    static let rim = NSColor(srgbRed: 214 / 255.0, green: 202 / 255.0, blue: 231 / 255.0, alpha: 1)
}

/// The SF Symbol the menu bar shows when Spotify is visible.
///
/// A literal rather than an import: pulling in HeadlessSpotifyBarKit would mean
/// building the package just to draw a picture, and the icon has to be
/// renderable on its own. scripts/check-icon-matches-menubar.sh fails the build
/// if the two ever drift apart.
let markSymbolName = "music.note"

// MARK: - Paths

/// `x^p` with the sign of `x` preserved, so the parametric superellipse stays
/// continuous as it crosses the axes. `pow(-0.0, 0.4)` is not a thing to rely on.
func signedPow(_ base: Double, _ exponent: Double) -> Double {
    let magnitude = pow(abs(base), exponent)
    return base < 0 ? -magnitude : magnitude
}

/// The macOS icon squircle, as a closed Core Graphics path.
func squirclePath(in rect: CGRect, exponent: Double) -> CGPath {
    let a = rect.width / 2
    // 720 segments over a full turn is half a degree each, which the
    // antialiaser hides completely at 1024px.
    let segments = 720
    let path = CGMutablePath()
    for index in 0...segments {
        let t = Double(index) / Double(segments) * 2 * .pi
        // 2/n, not n: parametrically the superellipse is |cos t|^(2/n).
        let power = 2 / exponent
        let x = rect.midX + a * signedPow(Foundation.cos(t), power)
        let y = rect.midY + a * signedPow(Foundation.sin(t), power)
        if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

// MARK: - The mark

/// The mark as a Core Graphics image, tinted white, `pointSize` points tall.
///
/// Returned as a `CGImage` rather than an `NSImage` on purpose. The rest of
/// this file draws through `CGContext` only and never establishes an
/// `NSGraphicsContext`, so an `NSImage.draw(in:)` here would composite into
/// whatever context happened to be current — which is how the first version of
/// this file shipped a disc with no mark on it and no error anywhere.
///
/// The tint is a white fill followed by a `destinationIn` composite, rather
/// than setting a fill colour and drawing the template image: whether a
/// template `NSImage` picks up the current colour from inside `draw(in:)` is
/// not worth betting an icon on. Filling first and then keeping only the
/// symbol's own alpha is the same result by construction.
func whiteMark(pointSize: Double) -> CGImage? {
    guard let base = NSImage(systemSymbolName: markSymbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
    else {
        // A missing SF Symbol would otherwise ship a blank disc, silently.
        FileHandle.standardError.write(Data("make-icon: SF Symbol '\(markSymbolName)' is unavailable\n".utf8))
        exit(1)
    }

    var proposed = CGRect(origin: .zero, size: base.size)
    guard let symbol = base.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
          symbol.width >= 1, symbol.height >= 1,
          let srgb = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: symbol.width,
              height: symbol.height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: srgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    let extent = CGRect(x: 0, y: 0, width: symbol.width, height: symbol.height)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(extent)
    context.setBlendMode(.destinationIn)
    context.draw(symbol, in: extent)
    return context.makeImage()
}

// MARK: - The icon

/// Draw the whole icon into an sRGB bitmap `size` pixels on a side.
func drawIcon(size: Double) -> NSBitmapImageRep {
    let pixels = Int(size.rounded())
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: pixels,
              height: pixels,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: srgb,
              // premultipliedLast, not noneSkipLast: the plate is an opaque
              // fill under a transparent surround, and skipping the alpha
              // premultiply turns the squircle's antialiased edge into a dark
              // fringe.
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        fatalError("could not allocate a \(pixels)×\(pixels) sRGB bitmap")
    }
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size / Canvas.master), y: CGFloat(size / Canvas.master))

    let master = CGRect(x: 0, y: 0, width: Canvas.master, height: Canvas.master)
    let inset = (Canvas.master - Canvas.plateSize) / 2
    let plate = master.insetBy(dx: inset, dy: inset)
    let centerX = master.midX
    let centerY = master.midY

    // 1. The plate, clipped to the squircle so nothing spills past the corners.
    context.saveGState()
    context.addPath(squirclePath(in: plate, exponent: Canvas.plateExponent))
    context.clip()
    context.drawLinearGradient(
        CGGradient(
            colorsSpace: srgb,
            colors: [Palette.plateTop.cgColor, Palette.plateBottom.cgColor] as CFArray,
            locations: [0, 1]
        )!,
        start: CGPoint(x: centerX, y: plate.maxY),
        end: CGPoint(x: centerX, y: plate.minY),
        options: []
    )

    // 2. The rim: a hairline ring outside the disc, as in Sonar, so the disc
    //    reads as inset rather than painted on.
    context.setStrokeColor(Palette.rim.cgColor)
    context.setLineWidth(Canvas.rimWidth)
    context.strokeEllipse(in: CGRect(
        x: centerX - Canvas.rimRadius,
        y: centerY - Canvas.rimRadius,
        width: Canvas.rimRadius * 2,
        height: Canvas.rimRadius * 2
    ))

    // 3. The disc and its ramp.
    context.saveGState()
    context.addEllipse(in: CGRect(
        x: centerX - Canvas.discRadius,
        y: centerY - Canvas.discRadius,
        width: Canvas.discRadius * 2,
        height: Canvas.discRadius * 2
    ))
    context.clip()
    // Anchored to the disc's own extremes along the 45° diagonal, which is what
    // makes the ramp reach each end of its range exactly at the disc's edge
    // instead of being cut short of it. Core Graphics counts y upwards, so the
    // top-left corner is the higher y.
    let reach = Canvas.discRadius / 2 * Foundation.sqrt(2)
    context.drawLinearGradient(
        CGGradient(
            colorsSpace: srgb,
            colors: [Palette.rampStart.cgColor, Palette.rampEnd.cgColor] as CFArray,
            locations: [0, 1]
        )!,
        start: CGPoint(x: centerX - reach, y: centerY + reach),
        end: CGPoint(x: centerX + reach, y: centerY - reach),
        options: []
    )

    // 4. The mark, white, centred, inside the disc's clip so an oversized symbol
    //    is cropped by the disc rather than overlapping the plate.
    if let mark = whiteMark(pointSize: Canvas.discRadius * Canvas.markScale) {
        // SF Symbols are not square — music.note is 12×15 — so the mark keeps
        // its own aspect and is centred on its real size. Drawing it into a
        // square would stretch it.
        let height = Canvas.discRadius * Canvas.markScale
        let width = height * Double(mark.width) / Double(mark.height)
        context.draw(mark, in: CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height))
    }
    context.restoreGState()  // disc clip
    context.restoreGState()  // plate clip

    guard let image = context.makeImage() else { fatalError("could not read back the rendered icon") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    return rep
}

// MARK: - Resizing

/// Resample to `targetPixels`, halving repeatedly and landing on the target.
///
/// Drawing 1024 straight down to 16 in one `draw` samples about four source
/// pixels per destination pixel, and the mark's antialiased edges alias
/// visibly at exactly the sizes the Dock and Finder use. Halving is a box
/// filter at every octave and is not.
func resample(_ image: CGImage, to targetPixels: Int, space: CGColorSpace) -> CGImage? {
    func draw(_ source: CGImage, _ pixels: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    var current = image
    var width = current.width
    while width / 2 >= targetPixels, width / 2 >= 1, let halved = draw(current, width / 2) {
        current = halved
        width = halved.width
    }
    if width == targetPixels { return current }
    return draw(current, targetPixels)
}

// MARK: - Output

/// Encode as a bare 8-bit RGBA PNG: no gamma chunk, no EXIF, no colour profile.
///
/// Not cosmetic. `NSBitmapImageRep.representation(using: .png, properties: [:])`
/// attaches an EXIF block to anything built from a `CGImage`, and IconServices
/// then silently rejects the 1024×1024 representation and falls back to a
/// generic grey plate for the whole icon — the artwork is fine and the app gets
/// a blank grey rounded square in the Dock, with nothing in any log. The icns
/// still builds, and `iconutil -c iconset` still round-trips all ten files, so
/// only looking at the rendered icon catches it.
func encodePNG(_ rep: NSBitmapImageRep) throws -> Data {
    let pixels = rep.pixelsWide, height = rep.pixelsHigh
    guard let source = rep.cgImage else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "no CGImage to encode"])
    }
    var bytes = [UInt8](repeating: 0, count: pixels * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: pixels,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: pixels * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not read back pixels"])
    }
    context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: height))
    guard let image = context.makeImage() else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not read back pixels"])
    }
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    return data
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    let data = try encodePNG(rep)
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func writePNG(master: NSBitmapImageRep, pixels: Int, to path: String) throws {
    guard let image = master.cgImage else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "no CGImage"])
    }
    if pixels == image.width {
        try writePNG(master, to: path)
        return
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let small = resample(image, to: pixels, space: space) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "resample to \(pixels)px failed"])
    }
    let rep = NSBitmapImageRep(cgImage: small)
    rep.size = NSSize(width: pixels, height: pixels)
    try writePNG(rep, to: path)
}

/// The .iconset layout `iconutil` expects, and the largest size we ship.
///
/// Deliberately no 1024×1024 entry — that is, no `icon_512x512@2x.png`.
///
/// The absence is load-bearing and was found the slow way. When the icns
/// contains a 1024 representation, IconServices decides the icon is a
/// modern-format asset and applies macOS's own rounded-rect mask and material
/// on top of it. The artwork here is *already* a squircle, so the result is the
/// squircle drawn inside a second squircle: a grey plate with a visible border
/// around the real icon. Remove the 1024 entry and IconServices uses the
/// artwork as-is, which is what Sonar's icns does — it ships 16/32/128 at 1x
/// and 2x and no 1024 either.
///
/// The failure is silent and survives every check that looks at the file:
/// `iconutil` succeeds, `iconutil -c iconset` round-trips all nine
/// representations back out, and `codesign --verify` passes. The only thing
/// that catches it is looking at the rendered icon, which is why
/// scripts/check-icon.sh renders it and asserts on the pixels.
///
/// 512 is the largest size macOS will ask for in practice, so nothing is lost.
let iconsetSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
]

func writeICNS(to path: String) throws {
    let fileManager = FileManager.default
    let iconset = path + ".iconset"
    try? fileManager.removeItem(atPath: iconset)
    try fileManager.createDirectory(atPath: iconset, withIntermediateDirectories: true)

    // Rendered once at the master size and reduced per target, so all ten files
    // come from identical pixels rather than ten independent renders.
    let master = drawIcon(size: Canvas.master)
    for entry in iconsetSizes {
        try writePNG(master: master, pixels: entry.pixels, to: "\(iconset)/\(entry.name).png")
    }

    try? fileManager.removeItem(atPath: path)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset, "-o", path]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    // The iconset is an intermediate. Leaving it behind would ship ten extra
    // PNGs inside the app bundle and break the ad-hoc signature's seal.
    try? fileManager.removeItem(atPath: iconset)
    guard process.terminationStatus == 0, fileManager.fileExists(atPath: path) else {
        throw NSError(
            domain: "make-icon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed to build \(path)"]
        )
    }
}

func flagValue(_ flag: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

// MARK: - Main

do {
    if let path = flagValue("--logo") ?? flagValue("--preview") {
        let size = flagValue("--size").flatMap(Double.init) ?? 512
        try writePNG(master: drawIcon(size: Canvas.master), pixels: Int(size), to: path)
        print("wrote \(path) (\(Int(size))px)")
    } else if CommandLine.arguments.count > 1, !CommandLine.arguments[1].hasPrefix("--") {
        try writeICNS(to: CommandLine.arguments[1])
        print("wrote \(CommandLine.arguments[1])")
    } else {
        FileHandle.standardError.write(
            Data("usage: make-icon.swift <out.icns> | --logo <out.png> | --preview <out.png> [--size N]\n".utf8)
        )
        exit(64)
    }
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
