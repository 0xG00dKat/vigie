// Dessine le logo de Vigie : un œil de vigie dont la pupille est une petite liste triée
// (les processus rangés par taille). Produit :
//   Support/AppIcon.icns          icône de l'app (Finder, Spotlight)
//   Support/MenuBarIcon(.png|@2x) icône de barre des menus (modèle monochrome)
//   [aperçu.png]                  planche d'aperçu, si un chemin est donné
// Usage : swift scripts/make-icon.swift [chemin-aperçu.png]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func save(_ context: CGContext, _ path: String) {
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
}

let navy: UInt32 = 0x1B2650

/// Contour de l'œil, en amande, centré sur (512, 512) dans une grille de 1024.
func eyePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 214, y: 512))
    path.addCurve(to: CGPoint(x: 810, y: 512), control1: CGPoint(x: 356, y: 716), control2: CGPoint(x: 668, y: 716))
    path.addCurve(to: CGPoint(x: 214, y: 512), control1: CGPoint(x: 668, y: 308), control2: CGPoint(x: 356, y: 308))
    path.closeSubpath()
    return path
}

/// Icône d'app, dessinée directement à chaque taille pour rester nette.
func drawIcon(_ context: CGContext, size: CGFloat, at origin: CGPoint = .zero) {
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    context.scaleBy(x: size / 1024, y: size / 1024)
    let tiny = size <= 32

    // Fond : carré arrondi de la grille macOS (824 px dans 1024), avec son ombre.
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: color(0x000000, 0.32))
    context.addPath(body)
    context.setFillColor(color(navy))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(gradient([color(0x24346B), color(0x0F5C6E)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Lueur chaude derrière l'œil : la vigie veille de nuit.
    context.drawRadialGradient(
        gradient([color(0xFFB547, 0.20), color(0xFFB547, 0)]),
        startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: []
    )
    // Reflet discret en haut.
    context.drawLinearGradient(gradient([color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 700), options: [])
    context.restoreGState()

    // Œil.
    context.addPath(eyePath())
    context.setFillColor(color(0x08102A, 0.42))
    context.fillPath()
    context.addPath(eyePath())
    context.setStrokeColor(color(0xFFFFFF))
    context.setLineWidth(tiny ? 74 : 48)
    context.setLineJoin(.round)
    context.strokePath()

    // Iris ambre.
    let radius: CGFloat = tiny ? 132 : 124
    context.saveGState()
    context.addEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
    context.clip()
    context.drawLinearGradient(gradient([color(0xFFD166), color(0xFF8A3D)]), start: CGPoint(x: 512, y: 512 + radius), end: CGPoint(x: 512, y: 512 - radius), options: [])
    context.restoreGState()

    context.setFillColor(color(navy))
    if tiny {
        // Trop petit pour la liste : une simple pupille.
        context.fillEllipse(in: CGRect(x: 512 - 56, y: 512 - 56, width: 112, height: 112))
    } else {
        // Pupille : trois lignes triées de la plus longue à la plus courte.
        let bars: [(y: CGFloat, width: CGFloat)] = [(552, 136), (512, 106), (472, 76)]
        for bar in bars {
            let rect = CGRect(x: 444, y: bar.y - 12, width: bar.width, height: 24)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        }
        context.fillPath()
        // Petit reflet de vie.
        context.setFillColor(color(0xFFFFFF, 0.9))
        context.fillEllipse(in: CGRect(x: 566, y: 570, width: 30, height: 30))
    }
    context.restoreGState()
}

/// Icône de barre des menus (18 × 18 pt) : même œil, en modèle monochrome que macOS colore lui-même.
func drawMenuGlyph(_ context: CGContext, scale: CGFloat, ink: CGColor, at origin: CGPoint = .zero) {
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    context.scaleBy(x: scale, y: scale)

    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: 1.1, y: 9))
    eye.addCurve(to: CGPoint(x: 16.9, y: 9), control1: CGPoint(x: 4.9, y: 14.6), control2: CGPoint(x: 13.1, y: 14.6))
    eye.addCurve(to: CGPoint(x: 1.1, y: 9), control1: CGPoint(x: 13.1, y: 3.4), control2: CGPoint(x: 4.9, y: 3.4))
    eye.closeSubpath()
    context.addPath(eye)
    context.setStrokeColor(ink)
    context.setLineWidth(1.4)
    context.setLineJoin(.round)
    context.strokePath()

    context.setFillColor(ink)
    context.fillEllipse(in: CGRect(x: 9 - 3.5, y: 9 - 3.5, width: 7, height: 7))
    // Les trois lignes sont découpées dans la pupille.
    context.setBlendMode(.clear)
    for bar in [(y: 10.35, width: 4.0), (y: 9.0, width: 3.1), (y: 7.65, width: 2.2)] as [(y: CGFloat, width: CGFloat)] {
        context.fill(CGRect(x: 7.0, y: bar.y - 0.42, width: bar.width, height: 0.84))
    }
    context.restoreGState()
}

// MARK: - Fichiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let support = root.appendingPathComponent("Support")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = base * factor
        let context = makeContext(pixels, pixels)
        drawIcon(context, size: CGFloat(pixels))
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        save(context, iconset.appendingPathComponent(name).path)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", support.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Support/AppIcon.icns" : "iconutil a échoué")

for factor in [1, 2] {
    let context = makeContext(18 * factor, 18 * factor)
    drawMenuGlyph(context, scale: CGFloat(factor), ink: color(0x000000))
    let name = factor == 1 ? "MenuBarIcon.png" : "MenuBarIcon@2x.png"
    save(context, support.appendingPathComponent(name).path)
    print("Support/\(name)")
}

// MARK: - Planche d'aperçu

if CommandLine.arguments.count > 1 {
    let width = 1240, height = 760
    let context = makeContext(width, height)
    context.setFillColor(color(0xF4F4F6))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawIcon(context, size: 560, at: CGPoint(x: 30, y: 170))
    var x: CGFloat = 640
    for size in [256, 128, 64, 32, 16] as [CGFloat] {
        drawIcon(context, size: size, at: CGPoint(x: x, y: 470))
        x += size + 24
    }

    // Barres de menus claire et sombre, icône à taille réelle (Retina) puis agrandie.
    for (index, dark) in [false, true].enumerated() {
        let y: CGFloat = CGFloat(300 - index * 130)
        context.setFillColor(color(dark ? 0x2A2A2E : 0xE6E6EA))
        context.fill(CGRect(x: 640, y: y, width: 570, height: 76))
        let ink = color(dark ? 0xFFFFFF : 0x000000, dark ? 0.92 : 0.85)
        // Dessinée à part puis collée : la découpe des lignes ne doit pas trouer le fond de la barre.
        for (scale, glyphX) in [(CGFloat(2), CGFloat(666)), (CGFloat(4), CGFloat(760))] {
            let pixels = Int(18 * scale)
            let glyph = makeContext(pixels, pixels)
            drawMenuGlyph(glyph, scale: scale, ink: ink)
            context.draw(glyph.makeImage()!, in: CGRect(x: glyphX, y: y + (76 - CGFloat(pixels)) / 2, width: CGFloat(pixels), height: CGFloat(pixels)))
        }
    }
    save(context, CommandLine.arguments[1])
    print("Aperçu : \(CommandLine.arguments[1])")
}
