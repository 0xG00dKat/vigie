import Foundation
import XCTest
@testable import VigieCore

final class LargeFilesTests: FrenchTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-doublons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, _ data: Data, modified: Date? = nil) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url.path
    }

    private func random(_ count: Int, seed: UInt8) -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255, using: &generator) ^ seed }
        return Data(bytes)
    }

    func testFileCategories() {
        XCTAssertEqual(FileCategory(path: "/a/Vacances.MOV"), .video)
        XCTAssertEqual(FileCategory(path: "/a/scan.heic"), .image)
        XCTAssertEqual(FileCategory(path: "/a/Xcode.xip"), .archive)
        XCTAssertEqual(FileCategory(path: "/a/Rapport.pdf"), .document)
        XCTAssertEqual(FileCategory(path: "/a/modele.gguf"), .other)
    }

    func testFilterByTypeAndAge() {
        let now = Date()
        func entry(_ name: String, lastUsed: Date?, modified: Date) -> StorageEntry {
            var entry = StorageEntry(id: "file:/" + name, title: L(name, name), explanation: L("", ""), kind: .largeFile,
                                     path: "/Users/test/Movies/" + name, size: 200_000_000, modified: modified)
            entry.lastUsed = lastUsed
            return entry
        }
        let year = now.addingTimeInterval(-365 * 86_400)
        let files = [
            entry("ancienne.mov", lastUsed: year, modified: year),
            // Modifiée il y a longtemps mais regardée hier : pas « inutilisée ».
            entry("regardee.mov", lastUsed: now.addingTimeInterval(-86_400), modified: year),
            entry("archive.zip", lastUsed: nil, modified: year),
        ]
        XCTAssertEqual(LargeFileFilter(category: .video).apply(files, now: now).map(\.title.fr), ["ancienne.mov", "regardee.mov"])
        XCTAssertEqual(LargeFileFilter(unusedOnly: true).apply(files, now: now).map(\.title.fr), ["ancienne.mov", "archive.zip"])
        XCTAssertEqual(LargeFileFilter(category: .video, unusedOnly: true).apply(files, now: now).map(\.title.fr), ["ancienne.mov"])
        XCTAssertFalse(LargeFileFilter().isActive)
        // Plusieurs types à la fois.
        XCTAssertEqual(LargeFileFilter(categories: [.video, .archive]).apply(files, now: now).count, 3)
    }

    func testLargeFilesGoToTrashOnlyInsideHome() {
        let file = StorageEntry(id: "file:x", title: L("x", "x"), explanation: L("", ""), kind: .largeFile,
                                path: "/Users/test/Downloads/film.mov", size: 1)
        XCTAssertEqual(StorageCleaner.cleanup(for: file, home: "/Users/test"), .trash)
        var outside = file
        outside.path = "/Volumes/Disque/film.mov"
        XCTAssertNil(StorageCleaner.cleanup(for: outside, home: "/Users/test"))
    }

    func testDuplicatesAreFoundByContentNotByName() throws {
        let photo = random(300_000, seed: 1)
        let old = Date().addingTimeInterval(-30 * 86_400)
        let original = try write("Documents/Photos/plage.jpg", photo, modified: old)
        let copy = try write("Downloads/plage (1).jpg", photo)
        let renamed = try write("Desktop/autre nom.jpg", photo)
        // Même taille, même début et même fin, mais un octet diffère au milieu : pas un doublon.
        var almost = photo
        almost[150_000] ^= 0xFF
        _ = try write("Desktop/presque.jpg", almost)
        // Même nom, contenu différent : pas un doublon.
        _ = try write("Desktop/Photos/plage.jpg", random(300_000, seed: 2))

        let groups = DuplicateFinder.group(try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .map { root.path + "/" + $0 }.filter { !$0.hasSuffix("Photos") && !$0.hasSuffix("Documents") && !$0.hasSuffix("Desktop") && !$0.hasSuffix("Downloads") })
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(Set(group.files.map(\.path)), [original, copy, renamed])
        // À garder : l'original (pas « (1) », pas dans Téléchargements, le plus ancien).
        XCTAssertEqual(group.files.first?.path, original)
        XCTAssertEqual(Set(group.others()), [copy, renamed])
        XCTAssertEqual(Set(group.others(keeping: copy)), [original, renamed])
        XCTAssertEqual(group.size, 300_000)
        XCTAssertGreaterThan(group.freed(), 0)
    }

    func testFinderSkipsCodeProjectsAndHardLinks() throws {
        let data = random(1_200_000, seed: 3)
        let first = try write("Documents/rapport.pdf", data)
        _ = try write("Documents/site/.git/HEAD", Data("ref".utf8))
        _ = try write("Documents/site/public/rapport.pdf", data)
        try FileManager.default.linkItem(atPath: first, toPath: root.path + "/Documents/lien.pdf")

        let groups = DuplicateFinder.find(roots: [root.path + "/Documents"])
        XCTAssertTrue(groups.isEmpty, "le fichier du projet et le lien physique ne sont pas des doublons à jeter")

        let other = random(1_100_000, seed: 5)
        let kept = try write("Documents/devis.pdf", other)
        let second = try write("Desktop/devis copie.pdf", other)
        let found = DuplicateFinder.find(roots: [root.path + "/Documents", root.path + "/Desktop"])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.files.map(\.path).sorted(), [second, kept].sorted())
        XCTAssertEqual(found.first?.files.first?.path, kept)
    }

    func testCopyNames() {
        XCTAssertTrue(DuplicateFinder.looksLikeCopy("/a/photo (1).jpg"))
        XCTAssertTrue(DuplicateFinder.looksLikeCopy("/a/Rapport copie.pdf"))
        XCTAssertTrue(DuplicateFinder.looksLikeCopy("/a/notes copy 2.txt"))
        XCTAssertFalse(DuplicateFinder.looksLikeCopy("/a/photo.jpg"))
        XCTAssertFalse(DuplicateFinder.looksLikeCopy("/a/facture-2024.pdf"))
    }

    func testCloneFreesAlmostNothing() throws {
        let path = try write("Documents/video.mov", random(2_000_000, seed: 4))
        let clone = root.path + "/Documents/video clone.mov"
        // `cp -c` fait un clone APFS, comme « Dupliquer » dans le Finder.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-c", path, clone]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let size = LargeFiles.privateSize(clone) else {
            throw XCTSkip("disque sans clones APFS")
        }
        // Les deux partagent leurs blocs : jeter l'un ou l'autre ne libère presque rien.
        XCTAssertLessThan(size, 100_000)
        XCTAssertLessThan(LargeFiles.privateSize(path) ?? .max, 100_000)
        let alone = try write("Documents/seule.mov", random(2_000_000, seed: 6))
        XCTAssertGreaterThan(LargeFiles.privateSize(alone) ?? 0, 1_500_000)
    }

    func testLibraryPackagesAreSkipped() {
        XCTAssertTrue(DiskUsage.isLibraryPackage("Photos Library.photoslibrary"))
        XCTAssertTrue(DiskUsage.isLibraryPackage("Mon film.imovielibrary"))
        XCTAssertFalse(DiskUsage.isLibraryPackage("Vacances"))
    }
}
