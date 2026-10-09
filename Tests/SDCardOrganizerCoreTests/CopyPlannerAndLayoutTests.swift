import XCTest
@testable import SDCardOrganizerCore

final class CopyPlannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    func testNoExistingFileReturnsCopyAsIs() throws {
        let source = try makeFile(name: "a.mov", content: "hello")
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let decision = CopyPlanner.decision(
            source: source, destinationDirectory: destDir, verifyChecksums: false, existingNames: []
        )
        guard case .copyAsIs(let url) = decision else {
            return XCTFail("Expected copyAsIs, got \(decision)")
        }
        XCTAssertEqual(url.lastPathComponent, "a.mov")
    }

    func testSameSizeSkipsAsDuplicate() throws {
        let source = try makeFile(name: "source.mov", content: "AAAA")
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let existing = try makeFile(name: "dest/clip.mov", content: "BBBB") // ta sama długość

        // Skopiuj istniejący plik pod nazwę źródła, by symulować duplikat.
        let duplicate = destDir.appendingPathComponent("source.mov")
        try FileManager.default.copyItem(at: existing, to: duplicate)

        let decision = CopyPlanner.decision(
            source: source, destinationDirectory: destDir, verifyChecksums: false, existingNames: ["source.mov"]
        )
        XCTAssertEqual(decision, .skipDuplicate)
    }

    func testSameNameDifferentSizeRenames() throws {
        let source = try makeFile(name: "clip.mov", content: "LONGER CONTENT")
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        // Istnieje plik o tej samej nazwie, ale innej wielkości.
        try "x".data(using: .utf8)!.write(to: destDir.appendingPathComponent("clip.mov"))

        let decision = CopyPlanner.decision(
            source: source, destinationDirectory: destDir, verifyChecksums: false, existingNames: ["clip.mov"]
        )
        guard case .copy(let url) = decision else {
            return XCTFail("Expected copy with unique name, got \(decision)")
        }
        XCTAssertEqual(url.lastPathComponent, "clip_1.mov")
    }

    func testChecksumVerificationDistinguishesContent() throws {
        let source = try makeFile(name: "clip.mov", content: "AAAA")
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        // Ta sama długość, inna treść -> nie duplikat przy włączonym checksum.
        try "BBBB".data(using: .utf8)!.write(to: destDir.appendingPathComponent("clip.mov"))

        let decision = CopyPlanner.decision(
            source: source, destinationDirectory: destDir, verifyChecksums: true, existingNames: ["clip.mov"]
        )
        guard case .copy(let url) = decision else {
            return XCTFail("Expected copy, got \(decision)")
        }
        XCTAssertEqual(url.lastPathComponent, "clip_1.mov")
    }
}

final class ProjectLayoutTests: XCTestCase {
    func testSanitizesProjectName() {
        XCTAssertEqual(ProjectLayout.sanitize("Mój Projekt / Karta 1"), "Mój Projekt - Karta 1")
        XCTAssertEqual(ProjectLayout.sanitize("   "), "Projekt")
        XCTAssertEqual(ProjectLayout.sanitize("a/b\\c?d*e"), "a-b-c-d-e")
    }

    func testBuildsFolderStructurePaths() {
        let layout = ProjectLayout(destinationRoot: "/Volumes/Dysk", projectName: "Mój Projekt")
        XCTAssertTrue(layout.root.path.contains("Mój Projekt"))
        XCTAssertEqual(layout.videoDir.lastPathComponent, "Video")
        XCTAssertEqual(layout.audioDir.lastPathComponent, "Audio")
        XCTAssertEqual(layout.photoDir.lastPathComponent, "Zdjęcia")
        XCTAssertEqual(layout.daVinciDir.lastPathComponent, "DaVinci")
    }

    func testFolderNameHasDatePrefix() {
        let date = ISO8601DateFormatter().date(from: "2026-10-09T10:00:00Z")!
        let name = ProjectLayout.folderName(projectName: "Test", date: date)
        XCTAssertTrue(name.hasPrefix("2026-10-09_"))
        XCTAssertTrue(name.hasSuffix("_Test"))
    }
}
