import SwiftUI

/// Icônes de Vigie, dessinées sur mesure (pas des SF Symbols) pour les boutons : formes pleines et arrondies en gris
/// clair, un fin liseré blanc sur le bord (relief de plastique moulé), et des détails en gris foncé.
/// Chaque icône est dessinée sur une grille de 24 × 24.
enum VigieIcon: CaseIterable {
    case refresh, memory, trash, close, gear, chevronDown, disk, magnifier, bell, power
    case eye, gauge, chart, bulb, apps, terminal, cube, network, moon, blocks, wrench, folder, doc, person, battery

    /// L'icône de Vigie qui remplace un symbole système (nil : on garde le symbole).
    init?(symbol: String) {
        let base = symbol.replacingOccurrences(of: ".filled", with: "").replacingOccurrences(of: ".fill", with: "")
        switch base {
        case "arrow.clockwise", "arrow.triangle.2.circlepath": self = .refresh
        case "memorychip": self = .memory
        case "trash": self = .trash
        case "xmark", "xmark.circle": self = .close
        case "gearshape", "gearshape.2", "gear": self = .gear
        case "internaldrive", "externaldrive", "opticaldiscdrive": self = .disk
        case "magnifyingglass": self = .magnifier
        case "bell", "bell.badge": self = .bell
        case "power", "poweron": self = .power
        case "eye", "eye.circle", "eye.slash": self = .eye
        case "gauge.with.needle", "gauge.with.dots.needle.50percent", "speedometer": self = .gauge
        case "chart.xyaxis.line", "chart.bar", "chart.line.uptrend.xyaxis": self = .chart
        case "lightbulb": self = .bulb
        case "square.grid.2x2", "app", "app.dashed", "square.stack.3d.up": self = .apps
        case "terminal": self = .terminal
        case "shippingbox", "cube", "shippingbox.and.arrow.backward", "archivebox": self = .cube
        case "point.3.connected.trianglepath.dotted", "network", "wifi", "wifi.exclamationmark": self = .network
        case "moon", "moon.zzz": self = .moon
        case "square.grid.3x3.topleft", "rectangle.split.3x3": self = .blocks
        case "wrench.and.screwdriver", "hammer", "wrench": self = .wrench
        case "folder": self = .folder
        case "doc", "doc.text", "doc.questionmark", "doc.on.doc", "film", "photo": self = .doc
        case "person", "person.crop.circle": self = .person
        case "battery.75percent", "battery.100percent", "battery.100percent.bolt", "battery.25percent": self = .battery
        default: return nil
        }
    }

    struct Shapes {
        /// Partie principale, claire, avec liseré.
        var primary = Path()
        /// Partie secondaire pleine, gris foncé, dessinée dessous (le corps de l'engrenage).
        var under = Path()
        /// Détails gris foncé tracés par-dessus (fentes, grille).
        var details = Path()
        var detailWidth: CGFloat = 1.6
    }

    private static func stroke(_ path: Path, _ width: CGFloat) -> Path {
        path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    var shapes: Shapes {
        var s = Shapes()
        switch self {
        case .refresh:
            var arc = Path()
            arc.addArc(center: CGPoint(x: 12, y: 12.5), radius: 7, startAngle: .degrees(-60), endAngle: .degrees(235), clockwise: false)
            s.primary = Self.stroke(arc, 3.2)
            // Pointe pleine, coins adoucis (même sens de tracé que l'arc : pas de trou au remplissage).
            var head = Path()
            head.move(to: CGPoint(x: 12.4, y: 2.2))
            head.addLine(to: CGPoint(x: 20.2, y: 4.2))
            head.addLine(to: CGPoint(x: 15.6, y: 10.4))
            head.closeSubpath()
            s.primary = s.primary.union(head.union(Self.stroke(head, 1.4)))
        case .memory:
            s.primary = Path(roundedRect: CGRect(x: 5.5, y: 5.5, width: 13, height: 13), cornerRadius: 3.4)
            var pins = Path()
            for x in [9.0, 12.0, 15.0] {
                pins.move(to: CGPoint(x: x, y: 2.2)); pins.addLine(to: CGPoint(x: x, y: 4.4))
                pins.move(to: CGPoint(x: x, y: 19.6)); pins.addLine(to: CGPoint(x: x, y: 21.8))
                pins.move(to: CGPoint(x: 2.2, y: x)); pins.addLine(to: CGPoint(x: 4.4, y: x))
                pins.move(to: CGPoint(x: 19.6, y: x)); pins.addLine(to: CGPoint(x: 21.8, y: x))
            }
            s.under = Self.stroke(pins, 1.8)
            s.details = Path(roundedRect: CGRect(x: 9.5, y: 9.5, width: 5, height: 5), cornerRadius: 1.2)
            s.detailWidth = 1.6
        case .trash:
            var lid = Path()
            lid.move(to: CGPoint(x: 4.5, y: 6.6)); lid.addLine(to: CGPoint(x: 19.5, y: 6.6))
            lid.move(to: CGPoint(x: 9.8, y: 3.6)); lid.addLine(to: CGPoint(x: 14.2, y: 3.6))
            s.primary = Self.stroke(lid, 2.6)
            var body = Path()
            body.move(to: CGPoint(x: 6.2, y: 9))
            body.addLine(to: CGPoint(x: 17.8, y: 9))
            body.addLine(to: CGPoint(x: 16.8, y: 19.2))
            body.addQuadCurve(to: CGPoint(x: 14.8, y: 21), control: CGPoint(x: 16.6, y: 21))
            body.addLine(to: CGPoint(x: 9.2, y: 21))
            body.addQuadCurve(to: CGPoint(x: 7.2, y: 19.2), control: CGPoint(x: 7.4, y: 21))
            body.closeSubpath()
            s.primary.addPath(body)
            var grill = Path()
            for x in [10.2, 13.8] { grill.move(to: CGPoint(x: x, y: 12)); grill.addLine(to: CGPoint(x: x, y: 18)) }
            s.details = grill
            s.detailWidth = 1.6
        case .close:
            var cross = Path()
            cross.move(to: CGPoint(x: 6.5, y: 6.5)); cross.addLine(to: CGPoint(x: 17.5, y: 17.5))
            cross.move(to: CGPoint(x: 17.5, y: 6.5)); cross.addLine(to: CGPoint(x: 6.5, y: 17.5))
            s.primary = Self.stroke(cross, 3.2)
        case .gear:
            // Corps clair, six dents larges, moyeu creusé en foncé : lisible même à 16 points.
            var gear = Path()
            let teeth = 6
            for index in 0..<(teeth * 2) {
                let angle = Double(index) / Double(teeth * 2) * 2 * .pi - .pi / 2
                let radius: Double = index % 2 == 0 ? 10.2 : 7.4
                let half = .pi / Double(teeth * 2) * 0.62
                for delta in [-half, half] {
                    let point = CGPoint(x: 12 + radius * cos(angle + delta), y: 12 + radius * sin(angle + delta))
                    if gear.isEmpty { gear.move(to: point) } else { gear.addLine(to: point) }
                }
            }
            gear.closeSubpath()
            s.primary = gear.union(Self.stroke(gear, 1.6))
            s.details = Path(ellipseIn: CGRect(x: 9.2, y: 9.2, width: 5.6, height: 5.6))
            s.detailWidth = 2.6
        case .chevronDown:
            var chevron = Path()
            chevron.move(to: CGPoint(x: 6, y: 9.5)); chevron.addLine(to: CGPoint(x: 12, y: 15)); chevron.addLine(to: CGPoint(x: 18, y: 9.5))
            s.primary = Self.stroke(chevron, 2.6)
        case .disk:
            s.primary = Path(roundedRect: CGRect(x: 3, y: 7, width: 18, height: 10.5), cornerRadius: 3.4)
            var slot = Path()
            slot.move(to: CGPoint(x: 6.5, y: 13.6)); slot.addLine(to: CGPoint(x: 11.5, y: 13.6))
            slot.addEllipse(in: CGRect(x: 15.6, y: 12.6, width: 2, height: 2))
            s.details = slot
            s.detailWidth = 1.7
        case .magnifier:
            var ring = Path()
            ring.addEllipse(in: CGRect(x: 4, y: 4, width: 12, height: 12))
            ring.move(to: CGPoint(x: 15, y: 15)); ring.addLine(to: CGPoint(x: 20, y: 20))
            s.primary = Self.stroke(ring, 3)
        case .bell:
            var bell = Path()
            bell.move(to: CGPoint(x: 5, y: 17))
            bell.addLine(to: CGPoint(x: 19, y: 17))
            bell.addLine(to: CGPoint(x: 17.5, y: 14.8))
            bell.addLine(to: CGPoint(x: 17.5, y: 10.5))
            bell.addQuadCurve(to: CGPoint(x: 6.5, y: 10.5), control: CGPoint(x: 12, y: 2.5))
            bell.addLine(to: CGPoint(x: 6.5, y: 14.8))
            bell.closeSubpath()
            s.primary = Self.stroke(bell, 1.6)
            s.primary.addPath(bell)
            var clapper = Path()
            clapper.move(to: CGPoint(x: 10.2, y: 20)); clapper.addLine(to: CGPoint(x: 13.8, y: 20))
            s.under = Self.stroke(clapper, 2.2)
        case .power:
            var arc = Path()
            arc.addArc(center: CGPoint(x: 12, y: 13), radius: 7.2, startAngle: .degrees(-55), endAngle: .degrees(235), clockwise: false)
            s.primary = Self.stroke(arc, 3)
            var bar = Path()
            bar.move(to: CGPoint(x: 12, y: 3.5)); bar.addLine(to: CGPoint(x: 12, y: 11))
            s.primary.addPath(Self.stroke(bar, 3))
        case .eye:
            var eye = Path()
            eye.move(to: CGPoint(x: 2.5, y: 12))
            eye.addQuadCurve(to: CGPoint(x: 21.5, y: 12), control: CGPoint(x: 12, y: 1.5))
            eye.addQuadCurve(to: CGPoint(x: 2.5, y: 12), control: CGPoint(x: 12, y: 22.5))
            eye.closeSubpath()
            s.primary = eye
            s.details = Path(ellipseIn: CGRect(x: 9, y: 9, width: 6, height: 6))
            s.detailWidth = 2.6
        case .gauge:
            // Arc et aiguille clairs, épais : lisible à petite taille.
            var arc = Path()
            arc.addArc(center: CGPoint(x: 12, y: 14.5), radius: 8.2, startAngle: .degrees(165), endAngle: .degrees(15), clockwise: false)
            s.primary = Self.stroke(arc, 3.4)
            var needle = Path()
            needle.move(to: CGPoint(x: 12, y: 14.5)); needle.addLine(to: CGPoint(x: 16.2, y: 9.2))
            s.primary = s.primary.union(Self.stroke(needle, 3)).union(Path(ellipseIn: CGRect(x: 9.6, y: 12.1, width: 4.8, height: 4.8)))
        case .chart:
            for (x, top) in [(5.0, 13.0), (10.5, 7.0), (16.0, 10.0)] {
                s.primary.addRoundedRect(in: CGRect(x: x, y: top, width: 3.6, height: 20 - top), cornerSize: CGSize(width: 1.8, height: 1.8))
            }
            var base = Path()
            base.move(to: CGPoint(x: 3.5, y: 20.5)); base.addLine(to: CGPoint(x: 20.5, y: 20.5))
            s.under = Self.stroke(base, 1.8)
        case .bulb:
            var bulb = Path()
            bulb.addArc(center: CGPoint(x: 12, y: 9.5), radius: 6.5, startAngle: .degrees(140), endAngle: .degrees(40), clockwise: false)
            bulb.addLine(to: CGPoint(x: 14.6, y: 16.5))
            bulb.addLine(to: CGPoint(x: 9.4, y: 16.5))
            bulb.closeSubpath()
            s.primary = bulb
            var base = Path()
            base.move(to: CGPoint(x: 9.6, y: 19)); base.addLine(to: CGPoint(x: 14.4, y: 19))
            base.move(to: CGPoint(x: 10.6, y: 21.4)); base.addLine(to: CGPoint(x: 13.4, y: 21.4))
            s.under = Self.stroke(base, 1.8)
        case .apps:
            for (x, y) in [(4.0, 4.0), (13.0, 4.0), (4.0, 13.0), (13.0, 13.0)] {
                s.primary.addRoundedRect(in: CGRect(x: x, y: y, width: 7, height: 7), cornerSize: CGSize(width: 2.2, height: 2.2))
            }
        case .terminal:
            s.primary = Path(roundedRect: CGRect(x: 3, y: 4.5, width: 18, height: 15), cornerRadius: 3.6)
            var prompt = Path()
            prompt.move(to: CGPoint(x: 7, y: 9.5)); prompt.addLine(to: CGPoint(x: 10, y: 12)); prompt.addLine(to: CGPoint(x: 7, y: 14.5))
            prompt.move(to: CGPoint(x: 12, y: 15)); prompt.addLine(to: CGPoint(x: 16.5, y: 15))
            s.details = prompt
            s.detailWidth = 1.8
        case .cube:
            var cube = Path()
            cube.move(to: CGPoint(x: 12, y: 2.8))
            cube.addLine(to: CGPoint(x: 20.2, y: 7.2)); cube.addLine(to: CGPoint(x: 20.2, y: 16.8))
            cube.addLine(to: CGPoint(x: 12, y: 21.2)); cube.addLine(to: CGPoint(x: 3.8, y: 16.8)); cube.addLine(to: CGPoint(x: 3.8, y: 7.2))
            cube.closeSubpath()
            s.primary = cube.union(Self.stroke(cube, 1.4))
            var edges = Path()
            edges.move(to: CGPoint(x: 4.5, y: 7.6)); edges.addLine(to: CGPoint(x: 12, y: 11.6)); edges.addLine(to: CGPoint(x: 19.5, y: 7.6))
            edges.move(to: CGPoint(x: 12, y: 11.6)); edges.addLine(to: CGPoint(x: 12, y: 20.4))
            s.details = edges
            s.detailWidth = 1.5
        case .network:
            var links = Path()
            links.move(to: CGPoint(x: 6, y: 17.5)); links.addLine(to: CGPoint(x: 12, y: 6.5)); links.addLine(to: CGPoint(x: 18, y: 17.5)); links.addLine(to: CGPoint(x: 6, y: 17.5))
            s.under = Self.stroke(links, 1.8)
            for (x, y) in [(12.0, 6.5), (6.0, 17.5), (18.0, 17.5)] {
                s.primary.addEllipse(in: CGRect(x: x - 3.4, y: y - 3.4, width: 6.8, height: 6.8))
            }
        case .moon:
            let outer = Path(ellipseIn: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            let bite = Path(ellipseIn: CGRect(x: 9.5, y: 1, width: 15, height: 15))
            s.primary = outer.subtracting(bite)
        case .blocks:
            s.primary.addRoundedRect(in: CGRect(x: 3, y: 3, width: 10.5, height: 18), cornerSize: CGSize(width: 2.4, height: 2.4))
            s.primary.addRoundedRect(in: CGRect(x: 15, y: 3, width: 6, height: 8.2), cornerSize: CGSize(width: 2, height: 2))
            s.primary.addRoundedRect(in: CGRect(x: 15, y: 12.8, width: 6, height: 8.2), cornerSize: CGSize(width: 2, height: 2))
        case .wrench:
            var handle = Path()
            handle.move(to: CGPoint(x: 6, y: 18)); handle.addLine(to: CGPoint(x: 13, y: 11))
            s.primary = Self.stroke(handle, 3.6)
            let head = Path(ellipseIn: CGRect(x: 11, y: 3, width: 10, height: 10))
            let notch = Path(roundedRect: CGRect(x: 15.2, y: 1.5, width: 3.6, height: 7), cornerRadius: 1.4)
                .applying(CGAffineTransform(translationX: 17, y: 5).rotated(by: .pi / 4).translatedBy(x: -17, y: -5))
            s.primary = s.primary.union(head.subtracting(notch))
        case .folder:
            var folder = Path()
            folder.move(to: CGPoint(x: 3, y: 7))
            folder.addQuadCurve(to: CGPoint(x: 5, y: 5), control: CGPoint(x: 3, y: 5))
            folder.addLine(to: CGPoint(x: 9.5, y: 5)); folder.addLine(to: CGPoint(x: 11.5, y: 7.5))
            folder.addLine(to: CGPoint(x: 19, y: 7.5))
            folder.addQuadCurve(to: CGPoint(x: 21, y: 9.5), control: CGPoint(x: 21, y: 7.5))
            folder.addLine(to: CGPoint(x: 21, y: 17.5))
            folder.addQuadCurve(to: CGPoint(x: 19, y: 19.5), control: CGPoint(x: 21, y: 19.5))
            folder.addLine(to: CGPoint(x: 5, y: 19.5))
            folder.addQuadCurve(to: CGPoint(x: 3, y: 17.5), control: CGPoint(x: 3, y: 19.5))
            folder.closeSubpath()
            s.primary = folder
            var lip = Path()
            lip.move(to: CGPoint(x: 3.8, y: 10.2)); lip.addLine(to: CGPoint(x: 20.2, y: 10.2))
            s.details = lip
            s.detailWidth = 1.4
        case .doc:
            var page = Path()
            page.move(to: CGPoint(x: 6, y: 4.5))
            page.addQuadCurve(to: CGPoint(x: 8, y: 2.5), control: CGPoint(x: 6, y: 2.5))
            page.addLine(to: CGPoint(x: 13.5, y: 2.5)); page.addLine(to: CGPoint(x: 18, y: 7))
            page.addLine(to: CGPoint(x: 18, y: 19.5))
            page.addQuadCurve(to: CGPoint(x: 16, y: 21.5), control: CGPoint(x: 18, y: 21.5))
            page.addLine(to: CGPoint(x: 8, y: 21.5))
            page.addQuadCurve(to: CGPoint(x: 6, y: 19.5), control: CGPoint(x: 6, y: 21.5))
            page.closeSubpath()
            s.primary = page
            var lines = Path()
            lines.move(to: CGPoint(x: 9, y: 12)); lines.addLine(to: CGPoint(x: 15, y: 12))
            lines.move(to: CGPoint(x: 9, y: 15.5)); lines.addLine(to: CGPoint(x: 13.5, y: 15.5))
            s.details = lines
            s.detailWidth = 1.6
        case .person:
            s.primary = Path(ellipseIn: CGRect(x: 8, y: 3, width: 8, height: 8))
            var body = Path()
            body.move(to: CGPoint(x: 4, y: 21))
            body.addQuadCurve(to: CGPoint(x: 20, y: 21), control: CGPoint(x: 12, y: 8))
            body.closeSubpath()
            s.primary.addPath(body.union(Self.stroke(body, 1.4)))
        case .battery:
            // Un contour (le disque est une pastille pleine) : la charge en bloc à gauche, la borne à droite.
            s.primary = Self.stroke(Path(roundedRect: CGRect(x: 2.5, y: 6.5, width: 17, height: 11), cornerRadius: 3.4), 2.2)
            s.primary.addPath(Path(roundedRect: CGRect(x: 5.6, y: 9.6, width: 8.4, height: 4.8), cornerRadius: 1.4))
            s.primary.addPath(Path(roundedRect: CGRect(x: 20.6, y: 10, width: 2.2, height: 4), cornerRadius: 1.1))
        }
        return s
    }
}

/// La tuile d'une icône, comme dans l'exemple choisi : carré gris foncé aux coins très arrondis, liseré clair en haut,
/// l'icône en relief au centre. Elle remplace les tuiles de couleur : une seule teinte pour toute l'app.
struct VigieIconTile: View {
    let icon: VigieIcon
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(DS.well)
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.5))
            .frame(width: size, height: size)
            .overlay(VigieGlyph(icon: icon, size: size * 0.64))
    }
}

/// Tuile de Vigie avec un symbole système (quand l'icône n'est pas encore dessinée).
struct VigieSymbolTile: View {
    let symbol: String
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(DS.well)
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.5))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(DS.primaryText.opacity(0.85))
            }
    }
}

/// Libellé de la barre latérale avec l'icône de Vigie (repli sur le symbole système s'il n'y en a pas).
struct SideLabel: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.secondaryText)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private func tile(size: CGFloat) -> some View {
        if let icon = VigieIcon(symbol: symbol) {
            VigieIconTile(icon: icon, size: size)
        } else {
            VigieSymbolTile(symbol: symbol, size: size)
        }
    }
}

/// Bulle d'aide AppKit (le nom au survol), transparente aux clics : la ligne reste sélectionnable et déplaçable.
struct AppKitToolTip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TipView {
        let view = TipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ view: TipView, context: Context) {
        if view.toolTip != text { view.toolTip = text }
    }

    final class TipView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Barre latérale réduite aux icônes (clé `barreCompacte`), par le bouton en bas de la barre.
enum SidebarCompact {
    static let key = "barreCompacte"
    static let width: CGFloat = 64
}

/// Les compteurs de la barre latérale disparaissent quand elle est réduite.
/// Pas de pastille vide : un compteur absent ou nul n'affiche rien (macOS dessinerait une bulle grise).
struct SideBadge: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if (value ?? "").isEmpty || value == "0" {
            content
        } else {
            content.badge(Text(value ?? ""))
        }
    }
}

extension View {
    func sideBadge(_ value: String?) -> some View { modifier(SideBadge(value: value)) }
}

/// Dessine une icône de Vigie dans son style : remplissage gris clair dégradé, liseré blanc intérieur, détails foncés.
/// `onColor` : sur un bouton coloré (le rouge), l'icône est presque blanche.
struct VigieGlyph: View {
    let icon: VigieIcon
    var size: CGFloat = 22
    var onColor = false
    var dimmed = false

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let shapes = icon.shapes
            let primary = shapes.primary.applying(transform)
            let under = shapes.under.applying(transform)
            let details = shapes.details.applying(transform)

            if !under.isEmpty {
                context.fill(under, with: .color(Color(white: onColor ? 0.95 : 0.30)))
                context.stroke(under, with: .color(Color.white.opacity(onColor ? 0 : 0.10)), lineWidth: 0.8 * scale)
            }
            let top = onColor ? Color.white : Color(white: dimmed ? 0.62 : 0.84)
            let bottom = onColor ? Color(white: 0.92) : Color(white: dimmed ? 0.48 : 0.66)
            context.fill(primary, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                        startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: canvasSize.height)))
            // Liseré blanc à l'intérieur du bord : le relief.
            context.drawLayer { layer in
                layer.clip(to: primary)
                layer.stroke(primary, with: .color(Color.white.opacity(onColor ? 0.55 : 0.95)), lineWidth: 1.5 * scale)
            }
            if !details.isEmpty {
                context.stroke(details, with: .color(Color(white: 0.20)),
                               style: StrokeStyle(lineWidth: shapes.detailWidth * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(onColor ? 0.25 : 0.55), radius: 0.6, y: 1)
    }
}

/// L'œil de Vigie, vivant : il cligne et grossit un peu au survol, cligne deux fois et envoie une onde au clic,
/// et l'onde revient doucement tant que le bilan travaille.
struct AnimatedEyeTile: View {
    var size: CGFloat = 34
    let hovering: Bool
    /// Change à chaque clic.
    let clicks: Int
    /// Le bilan est en cours : l'onde revient régulièrement.
    let scanning: Bool

    @State private var lid: CGFloat = 1
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0
    @State private var pressed = false
    @State private var lookOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // L'onde : un contour vert d'eau qui s'élargit et s'efface.
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(VigieTheme.accent, lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            // En vert d'eau, la couleur de Vigie : c'est le bouton principal de la colonne, pas une simple icône.
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [VigieTheme.accent.opacity(0.95), VigieTheme.accent], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: max(0.5, size / 40)))
                .frame(width: size, height: size)
                .overlay(
                    // Le logo de Vigie ; le clignement le referme à la verticale, le regard déplace l'iris.
                    LogoMark(color: .white, gap: max(0.6, size / 40), look: lookOffset / (size * 0.72), openness: lid)
                        .frame(width: size * 0.72)
                        .shadow(color: .black.opacity(0.2), radius: 0.6, y: 1)
                )
                .shadow(color: VigieTheme.accent.opacity(hovering ? 0.45 : 0.25), radius: hovering ? size / 5 : size / 9, y: size / 28)
                .scaleEffect(pressed ? 0.9 : hovering ? 1.08 : 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pressed)
        .onChange(of: hovering) {
            guard hovering else { return }
            Task { await look(); await blink() }
        }
        .onChange(of: clicks) {
            Task {
                pressed = true
                try? await Task.sleep(for: .milliseconds(110))
                pressed = false
                pulse()
                await blink()
                try? await Task.sleep(for: .milliseconds(90))
                await blink()
            }
        }
        .task(id: scanning) {
            while scanning, !Task.isCancelled {
                pulse()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    @MainActor
    private func blink() async {
        withAnimation(.easeIn(duration: 0.07)) { lid = 0.08 }
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.easeOut(duration: 0.14)) { lid = 1 }
        try? await Task.sleep(for: .milliseconds(140))
    }

    /// Un regard à gauche puis à droite, comme une vigie qui balaie l'horizon.
    @MainActor
    private func look() async {
        withAnimation(.easeInOut(duration: 0.16)) { lookOffset = -size * 0.05 }
        try? await Task.sleep(for: .milliseconds(170))
        withAnimation(.easeInOut(duration: 0.22)) { lookOffset = size * 0.05 }
        try? await Task.sleep(for: .milliseconds(230))
        withAnimation(.easeInOut(duration: 0.16)) { lookOffset = 0 }
    }

    private func pulse() {
        ringScale = 1
        ringOpacity = 0.85
        withAnimation(.easeOut(duration: 0.9)) {
            ringScale = 1.7
            ringOpacity = 0
        }
    }
}
