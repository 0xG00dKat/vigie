// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vigie",
    platforms: [.macOS(.v14)],
    targets: [
        // Lecture des processus, regroupement, explications. Sans AppKit : testable.
        .target(name: "VigieCore"),
        // App de barre des menus (SwiftUI + AppKit).
        .executableTarget(name: "Vigie", dependencies: ["VigieCore"]),
        .testTarget(name: "VigieCoreTests", dependencies: ["VigieCore"]),
    ],
    swiftLanguageModes: [.v5]
)
