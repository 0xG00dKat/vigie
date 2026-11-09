// Icône de barre des menus de Vigie, tirée du logo.
//
// Le logo vit dans `Support/Vigie.icon` (document Icon Composer : fond, 4 calques SVG, effet verre de macOS).
// `scripts/build-app.sh` le compile avec `actool` en `Assets.car` + `Vigie.icns` ; ce script ne s'en occupe pas.
// Il dessine seulement le modèle monochrome de la barre des menus à partir des mêmes calques :
//   Support/MenuBarIcon(.png|@2x)  modèle 18 × 18 pt que macOS colore lui-même
//   Sources/Vigie/LogoPaths.swift  les mêmes tracés pour l'app (bouton œil, animation d'ouverture)
//   [aperçu.png]                   planche d'aperçu agrandie, si un chemin est donné
// Usage : swift scripts/make-icon.swift [chemin-aperçu.png]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let support = root.appendingPathComponent("Support")
let assets = support.appendingPathComponent("Vigie.icon/Assets")

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ context: CGContext, _ path: String) {
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

/// Lit le tracé d'un calque SVG (commandes absolues M, L, C, Z sur une toile de 1024), axe y retourné pour Core Graphics.
func layer(_ name: String) -> (path: CGPath, evenOdd: Bool, data: String) {
    let svg = try! String(contentsOf: assets.appendingPathComponent(name), encoding: .utf8)
    let d = svg.components(separatedBy: " d=\"")[1].components(separatedBy: "\"")[0]
    let tokens = d.split(separator: " ").map(String.init)
    let path = CGMutablePath()
    var index = 0, command = ""
    func point() -> CGPoint {
        let x = Double(tokens[index])!, y = Double(tokens[index + 1])!
        index += 2
        return CGPoint(x: x, y: 1024 - y)
    }
    while index < tokens.count {
        if let first = tokens[index].first, first.isLetter {
            command = tokens[index]; index += 1
            if command == "Z" { path.closeSubpath() }
            continue
        }
        switch command {
        case "M": path.move(to: point()); command = "L"
        case "L": path.addLine(to: point())
        case "C": let c1 = point(), c2 = point(), end = point(); path.addCurve(to: end, control1: c1, control2: c2)
        default: index += 1
        }
    }
    return (path, svg.contains("evenodd"), d)
}

let layers = ["1-paupiere-haute.svg", "2-paupiere-gauche.svg", "3-paupiere-basse.svg", "4-iris.svg"].map(layer)

// MARK: - Tracés pour l'app (LogoMark, animation d'ouverture)

/// Cadre d'un tracé dans l'axe du SVG (y vers le bas).
func svgBox(_ path: CGPath) -> CGRect {
    let box = path.boundingBoxOfPath
    return CGRect(x: box.minX, y: 1024 - box.maxY, width: box.width, height: box.height)
}
func literal(_ rect: CGRect) -> String {
    String(format: "CGRect(x: %.2f, y: %.2f, width: %.2f, height: %.2f)", rect.minX, rect.minY, rect.width, rect.height)
}
let markBox = layers.map { svgBox($0.path) }.reduce(CGRect.null) { $0.union($1) }
let generated = """
// Généré par scripts/make-icon.swift à partir de Support/Vigie.icon : ne pas modifier à la main.
import CoreGraphics

/// Les tracés du logo (toile de 1024, axe y vers le bas comme le SVG).
enum LogoPaths {
    /// Cadre de l'œil entier.
    static let bounds = \(literal(markBox))
    /// Cadre de l'iris (centre de son agrandissement et de son regard).
    static let irisBounds = \(literal(svgBox(layers[3].path)))
    static let upperLid = "\(layers[0].data)"
    static let leftLid = "\(layers[1].data)"
    static let lowerLid = "\(layers[2].data)"
    static let iris = "\(layers[3].data)"
}

"""
try! generated.write(to: root.appendingPathComponent("Sources/Vigie/LogoPaths.swift"), atomically: true, encoding: .utf8)
print("Sources/Vigie/LogoPaths.swift")

/// Œil de 18 × 18 pt. Les fentes entre les morceaux sont élargies (contour effacé) pour rester visibles en petit.
func drawMenuGlyph(_ context: CGContext, scale: CGFloat, ink: CGColor) {
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    // L'œil fait 760 unités de large sur la toile de 1024 : 16,6 pt de large, centré.
    let unit: CGFloat = 16.6 / 760
    context.translateBy(x: 9, y: 9)
    context.scaleBy(x: unit, y: unit)
    context.translateBy(x: -512, y: -512)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(ink)
    for item in layers {
        context.addPath(item.path)
        context.fillPath(using: item.evenOdd ? .evenOdd : .winding)
    }
    context.setBlendMode(.clear)
    context.setLineWidth(0.55 / unit)
    context.setLineJoin(.round)
    for item in layers {
        context.addPath(item.path)
        context.strokePath()
    }
    context.endTransparencyLayer()
    context.restoreGState()
}

for factor in [1, 2] {
    let context = makeContext(18 * factor, 18 * factor)
    drawMenuGlyph(context, scale: CGFloat(factor), ink: CGColor(gray: 0, alpha: 1))
    let name = factor == 1 ? "MenuBarIcon.png" : "MenuBarIcon@2x.png"
    save(context, support.appendingPathComponent(name).path)
    print("Support/\(name)")
}

// Planche d'aperçu : barres des menus claire et sombre, taille réelle (Retina) puis agrandie.
if CommandLine.arguments.count > 1 {
    let width = 700, height = 300
    let sheet = makeContext(width, height)
    sheet.setFillColor(CGColor(gray: 0.96, alpha: 1))
    sheet.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, dark) in [false, true].enumerated() {
        let y = CGFloat(170 - index * 140)
        sheet.setFillColor(dark ? CGColor(gray: 0.17, alpha: 1) : CGColor(gray: 0.9, alpha: 1))
        sheet.fill(CGRect(x: 20, y: y, width: 660, height: 120))
        let ink = CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.92 : 0.85)
        for (scale, x) in [(CGFloat(2), CGFloat(50)), (CGFloat(6), CGFloat(130))] {
            let pixels = Int(18 * scale)
            let glyph = makeContext(pixels, pixels)
            drawMenuGlyph(glyph, scale: scale, ink: ink)
            sheet.draw(glyph.makeImage()!, in: CGRect(x: x, y: y + (120 - CGFloat(pixels)) / 2, width: CGFloat(pixels), height: CGFloat(pixels)))
        }
    }
    save(sheet, CommandLine.arguments[1])
    print("Aperçu : \(CommandLine.arguments[1])")
}
