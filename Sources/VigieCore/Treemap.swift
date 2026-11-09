import CoreGraphics
import Foundation

/// Carte en rectangles : chaque élément reçoit une surface proportionnelle à sa taille, en rectangles
/// aussi proches que possible du carré (algorithme « squarified » de Bruls, Huizing et van Wijk).
public enum Treemap {
    /// Rectangles dans l'ordre des tailles données (à trier de la plus grande à la plus petite).
    public static func layout(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return sizes.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { max($0, 0) * scale }
        var result = [CGRect](repeating: .zero, count: sizes.count)
        var remaining = rect
        var row: [Int] = []
        var index = 0

        func worst(_ row: [Int], side: Double) -> Double {
            let values = row.map { areas[$0] }
            let sum = values.reduce(0, +)
            guard sum > 0, let largest = values.max(), let smallest = values.min(), smallest > 0 else { return .infinity }
            return max(side * side * largest / (sum * sum), (sum * sum) / (side * side * smallest))
        }

        func place(_ row: [Int]) {
            let sum = row.reduce(0) { $0 + areas[$1] }
            guard sum > 0 else { return }
            if remaining.width >= remaining.height {
                // Une colonne à gauche.
                let width = CGFloat(sum) / remaining.height
                var y = remaining.minY
                for item in row {
                    let height = CGFloat(areas[item]) / width
                    result[item] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // Une rangée en haut.
                let height = CGFloat(sum) / remaining.width
                var x = remaining.minX
                for item in row {
                    let width = CGFloat(areas[item]) / height
                    result[item] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(0, remaining.height - height))
            }
        }

        while index < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [index], side: side) <= worst(row, side: side) {
                row.append(index)
                index += 1
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}

/// Explorateur de dossiers : ce qu'il y a dans un dossier, par taille, à partir d'une mesure sur plusieurs niveaux.
public struct FolderListing: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String { path }
        public var name: String
        public var path: String
        public var size: UInt64
        public var isDirectory: Bool

        public init(name: String, path: String, size: UInt64, isDirectory: Bool) {
            self.name = name
            self.path = path
            self.size = size
            self.isDirectory = isDirectory
        }
    }

    public var path: String
    public var size: UInt64
    public var items: [Item]
    /// Place des petits fichiers non listés un par un.
    public var other: UInt64
    /// Dossiers encore en cours de mesure (la carte se remplit pendant la mesure).
    public var pending: Int = 0

    public init(path: String, size: UInt64, items: [Item], other: UInt64, pending: Int = 0) {
        self.path = path
        self.size = size
        self.items = items
        self.other = other
        self.pending = pending
    }

    /// Contenu d'un dossier mesuré (lui-même ou un de ses sous-dossiers mémorisés), du plus gros au plus petit.
    public static func make(path: String, from result: DiskUsage.Result, root: String) -> FolderListing? {
        let size = path == root ? result.total : result.directorySizes[path]
        guard let size else { return nil }
        var items: [Item] = []
        for (child, childSize) in result.directorySizes where (child as NSString).deletingLastPathComponent == path {
            items.append(Item(name: (child as NSString).lastPathComponent, path: child, size: childSize, isDirectory: true))
        }
        for file in result.explorerFiles where (file.path as NSString).deletingLastPathComponent == path {
            items.append(Item(name: (file.path as NSString).lastPathComponent, path: file.path, size: file.size, isDirectory: false))
        }
        items.sort { $0.size > $1.size }
        let listed = items.reduce(UInt64(0)) { $0 + $1.size }
        return FolderListing(path: path, size: size, items: items, other: size > listed ? size - listed : 0)
    }
}
