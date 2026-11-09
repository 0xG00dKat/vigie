import SwiftUI

/// Les quatre morceaux du logo de Vigie (tracés générés dans `LogoPaths.swift`).
enum LogoPart: CaseIterable {
    case upperLid, leftLid, lowerLid, iris

    /// L'iris est percé d'un reflet : remplissage pair-impair.
    var evenOdd: Bool { self == .iris }

    /// Tracés lus une seule fois, sur la toile de 1024.
    static let paths: [LogoPart: Path] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, parse($0.data)) })

    private var data: String {
        switch self {
        case .upperLid: return LogoPaths.upperLid
        case .leftLid: return LogoPaths.leftLid
        case .lowerLid: return LogoPaths.lowerLid
        case .iris: return LogoPaths.iris
        }
    }

    /// Lit un tracé SVG simple (commandes absolues M, L, C, Z).
    private static func parse(_ data: String) -> Path {
        var path = Path()
        let tokens = data.split(separator: " ").map(String.init)
        var index = 0, command = ""
        func point() -> CGPoint {
            defer { index += 2 }
            return CGPoint(x: Double(tokens[index]) ?? 0, y: Double(tokens[index + 1]) ?? 0)
        }
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index]
                index += 1
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
        return path
    }
}

/// Un morceau du logo, placé comme dans l'œil entier : l'œil remplit le cadre, proportions gardées, centré.
struct LogoPartShape: Shape {
    let part: LogoPart

    func path(in rect: CGRect) -> Path {
        let bounds = LogoPaths.bounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return (LogoPart.paths[part] ?? Path()).applying(transform)
    }
}

/// Le logo de Vigie en une couleur : trois morceaux de paupière et l'iris.
/// `gap` élargit les fentes entre les morceaux (en points) pour qu'elles restent visibles en petit.
struct LogoMark: View {
    var color: Color = .white
    var gap: CGFloat = 0
    /// Regard : déplacement horizontal de l'iris, en fraction de la largeur de l'œil.
    var look: CGFloat = 0
    /// Ouverture (1 = ouvert, proche de 0 = fermé) : l'œil se referme à la verticale.
    var openness: CGFloat = 1

    static let aspectRatio = LogoPaths.bounds.width / LogoPaths.bounds.height

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(LogoPart.allCases, id: \.self) { part in
                    piece(part)
                        .offset(x: part == .iris ? look * geometry.size.width : 0)
                }
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .scaleEffect(x: 1, y: openness, anchor: .center)
    }

    private func piece(_ part: LogoPart) -> some View {
        LogoPartShape(part: part)
            .fill(color, style: FillStyle(eoFill: part.evenOdd))
            .overlay {
                if gap > 0 {
                    // Le bord de chaque morceau est effacé : les fentes s'élargissent.
                    LogoPartShape(part: part)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: gap, lineJoin: .round))
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
    }
}
