// makeicon.swift — maakt van een vierkante bronfoto een 1024×1024 app-icoon met
// "3D knop"-look: afgeronde squircle, zachte slagschaduw, glans bovenaan en een
// subtiele bevel-rand. Gebruikt enkel AppKit/CoreGraphics (geen externe tools).
//
// Gebruik:  makeicon <bron.png> <uit.png>

import AppKit
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("makeicon: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("gebruik: makeicon <bron.png> <uit.png>") }
let srcPath = args[1]
let outPath = args[2]

guard let src = NSImage(contentsOfFile: srcPath) else { fail("kan bron niet laden: \(srcPath)") }

let S: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fail("kan bitmap niet maken") }
rep.size = NSSize(width: S, height: S)

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fail("geen grafische context") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// --- Geometrie: kunstvlak met marge (macOS-stijl), afgeronde hoeken -----------
let inset: CGFloat = 92
let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius: CGFloat = rect.width * 0.2237      // squircle-achtige ronding
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// --- 1. Zachte slagschaduw onder de knop -------------------------------------
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -16),
             blur: 42,
             color: NSColor(white: 0, alpha: 0.38).cgColor)
cg.addPath(path)
cg.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
cg.fillPath()
cg.restoreGState()

// --- 2. Foto aspect-fill binnen de afgeronde vorm ----------------------------
cg.saveGState()
cg.addPath(path)
cg.clip()

let imgSize = src.size
let scale = max(rect.width / imgSize.width, rect.height / imgSize.height)
let drawW = imgSize.width * scale
let drawH = imgSize.height * scale
let drawRect = CGRect(x: rect.midX - drawW / 2, y: rect.midY - drawH / 2, width: drawW, height: drawH)
src.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)

// --- 3. Glans: lichte verloop bovenaan, donker hint onderaan (3D-bolling) -----
if let space = CGColorSpace(name: CGColorSpace.sRGB) {
    let glossColors = [
        NSColor(white: 1, alpha: 0.26).cgColor,
        NSColor(white: 1, alpha: 0.05).cgColor,
        NSColor(white: 1, alpha: 0.0).cgColor,
        NSColor(white: 0, alpha: 0.10).cgColor,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: glossColors,
                             locations: [0.0, 0.42, 0.62, 1.0]) {
        cg.drawLinearGradient(grad,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: [])
    }
}
cg.restoreGState()

// --- 4. Bevel-rand: brede, lichte opstaande rand (knopgevoel) -----------------
cg.saveGState()
cg.addPath(path)
cg.clip()
// brede lichte binnenrand — maakt de "opstaande knop"-rand duidelijk zichtbaar
cg.addPath(CGPath(roundedRect: rect.insetBy(dx: 11, dy: 11),
                  cornerWidth: radius * 0.92, cornerHeight: radius * 0.92, transform: nil))
cg.setStrokeColor(NSColor(white: 1, alpha: 0.62).cgColor)
cg.setLineWidth(22)
cg.strokePath()
// scherpe heldere lip aan de buitenste rand
cg.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2),
                  cornerWidth: radius, cornerHeight: radius, transform: nil))
cg.setStrokeColor(NSColor(white: 1, alpha: 0.85).cgColor)
cg.setLineWidth(4)
cg.strokePath()
cg.restoreGState()

// dunne, scherpe buitenrand voor definitie tegen de achtergrond
cg.saveGState()
cg.addPath(path)
cg.setStrokeColor(NSColor(white: 0, alpha: 0.22).cgColor)
cg.setLineWidth(2)
cg.strokePath()
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()

// --- Wegschrijven ------------------------------------------------------------
guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG-encode mislukt") }
do { try data.write(to: URL(fileURLWithPath: outPath)) }
catch { fail("schrijven mislukt: \(error)") }
