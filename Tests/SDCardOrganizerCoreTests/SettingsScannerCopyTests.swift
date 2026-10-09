import XCTest
@testable import SDCardOrganizerCore

final class SettingsAndScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSettingsRoundTrip() throws {
        var settings = Settings()
        settings.destinationRoot = "/Volumes/Dysk"
        settings.enabledExtensions = ["mov", "cr2"]
        settings.frameRate = 25

        let url = tempDir.appendingPathComponent("settings.json")
        try SettingsStore.save(settings, to: url)
        let loaded = try SettingsStore.load(from: url)

        XCTAssertEqual(loaded, settings)
    }

    func testLoadMissingFileReturnsDefaults() throws {
        let url = tempDir.appendingPathComponent("nonexistent.json")
        let loaded = try SettingsStore.load(from: url)
        XCTAssertFalse(loaded.enabledExtensions.isEmpty)
        XCTAssertEqual(loaded.frameRate, 25)
        XCTAssertEqual(loaded.resolution, "1920x1080")
    }

    func testScannerFindsMatchingFilesRecursively() throws {
        try "video".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("clip.mov"))
        let sub = tempDir.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "raw".data(using: .utf8)!.write(to: sub.appendingPathComponent("photo.CR2"))
        try "note".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("readme.txt"))

        let scanner = MediaScanner(enabledExtensions: ["mov", "cr2"])
        let results = try scanner.scan(volumeRoot: tempDir)

        XCTAssertEqual(results.count, 2)
        let names = Set(results.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("clip.mov"))
        XCTAssertTrue(names.contains("photo.CR2"))
    }

    func testScannerCategorizesFiles() throws {
        try "v".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("v.mp4"))
        try "a".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("a.wav"))
        try "p".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("p.jpg"))

        let scanner = MediaScanner(enabledExtensions: ["*"])
        let results = try scanner.scan(volumeRoot: tempDir)

        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.url.lastPathComponent, $0.category) })
        XCTAssertEqual(byName["v.mp4"], .video)
        XCTAssertEqual(byName["a.wav"], .audio)
        XCTAssertEqual(byName["p.jpg"], .photo)
    }
}

final class CopyServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCopyCreatesProjectAndFiles() throws {
        let sourceVolume = tempDir.appendingPathComponent("card", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVolume, withIntermediateDirectories: true)
        try "clip-content".data(using: .utf8)!.write(to: sourceVolume.appendingPathComponent("A001.MOV"))

        let destRoot = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)

        var settings = Settings()
        settings.destinationRoot = destRoot.path
        settings.enabledExtensions = ["mov"]

        let scanner = MediaScanner(enabledExtensions: settings.enabledExtensions)
        let files = try scanner.scan(volumeRoot: sourceVolume)

        let layout = ProjectLayout(destinationRoot: destRoot.path, projectName: "Testowy Projekt")
        let report = try CopyService(verifyChecksums: false).copy(files: files, to: layout)

        XCTAssertEqual(report.totalCopied, 1)
        XCTAssertEqual(report.totalSkipped, 0)
        XCTAssertEqual(report.totalBytesCopied, Int64("clip-content".utf8.count))

        // Sprawdź strukturę: Video/A001.MOV
        let copied = layout.videoDir.appendingPathComponent("A001.MOV")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        // Manifest i plik .drp
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.manifestURL().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.drpFileURL().path))
    }

    func testIngestHistoryPersistence() {
        let record = IngestRecord(
            projectName: "XCTestProject",
            sourceVolumeName: "SD_TEST",
            destinationPath: "/dest/test",
            filesCopied: 3,
            filesSkipped: 0,
            filesFailed: 0,
            totalBytes: 5000
        )
        IngestHistory.append(record)
        let loaded = IngestHistory.load()
        XCTAssertTrue(loaded.contains(where: { $0.projectName == "XCTestProject" }))
    }
}
