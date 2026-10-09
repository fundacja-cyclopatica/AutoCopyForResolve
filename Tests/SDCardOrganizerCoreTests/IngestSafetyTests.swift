import XCTest
@testable import SDCardOrganizerCore

/// Scenariusze bezpieczeństwa danych: migracja ustawień, dogrywanie do istniejącego
/// projektu, błędy pojedynczych plików i weryfikacja kopii.
final class IngestSafetyTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: – Ustawienia

    func testSettingsFromOlderVersionKeepUserValues() throws {
        // Plik zapisany przez wersję bez cameraPresets / openIn* / verifyCopies.
        let json = """
        {"destinationRoot":"/Volumes/SSD","enabledExtensions":["mov","arw"],
         "resolution":"3840x2160","frameRate":50,"verifyChecksums":true,
         "drpTemplatePath":"/Users/test/szablon.drp"}
        """
        let url = tempDir.appendingPathComponent("settings.json")
        try json.data(using: .utf8)!.write(to: url)

        let loaded = try SettingsStore.load(from: url)

        XCTAssertEqual(loaded.destinationRoot, "/Volumes/SSD")
        XCTAssertEqual(loaded.enabledExtensions, ["mov", "arw"])
        XCTAssertEqual(loaded.resolution, "3840x2160")
        XCTAssertEqual(loaded.frameRate, 50)
        XCTAssertTrue(loaded.verifyChecksums)
        XCTAssertEqual(loaded.drpTemplatePath, "/Users/test/szablon.drp")
        XCTAssertEqual(loaded.cameraPresets, Settings.defaultCameraPresets)
        XCTAssertTrue(loaded.verifyCopies)
    }

    func testFieldWithWrongTypeFallsBackToDefaultOnly() throws {
        let json = #"{"destinationRoot":"/Volumes/SSD","frameRate":"dwadzieścia pięć"}"#
        let url = tempDir.appendingPathComponent("settings.json")
        try json.data(using: .utf8)!.write(to: url)

        let loaded = try SettingsStore.load(from: url)

        XCTAssertEqual(loaded.destinationRoot, "/Volumes/SSD")
        XCTAssertEqual(loaded.frameRate, 25)
    }

    func testUnreadableSettingsFileIsBackedUp() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try "to nie jest JSON".data(using: .utf8)!.write(to: url)

        let loaded = try SettingsStore.load(from: url)

        XCTAssertEqual(loaded, Settings())
        let backups = try fm.contentsOfDirectory(atPath: tempDir.path).filter { $0.contains(".unreadable-") }
        XCTAssertEqual(backups.count, 1)
    }

    // MARK: – Dogrywanie do istniejącego projektu

    func testProjectCanBeBuiltTwiceWithTemplate() throws {
        let dest = try makeDir("dest")
        let template = tempDir.appendingPathComponent("szablon.drp")
        try "TEMPLATE".data(using: .utf8)!.write(to: template)

        var settings = Settings()
        settings.destinationRoot = dest.path
        settings.drpTemplatePath = template.path

        let first = try ProjectBuilder(settings: settings).build(projectName: "Wesele")
        let firstManifest = try manifest(of: first)
        let second = try ProjectBuilder(settings: settings).build(projectName: "Wesele")
        let secondManifest = try manifest(of: second)

        XCTAssertEqual(first.root, second.root)
        XCTAssertEqual(try String(contentsOf: second.drpFileURL(), encoding: .utf8), "TEMPLATE")
        XCTAssertEqual(firstManifest["createdAt"] as? String, secondManifest["createdAt"] as? String)
        XCTAssertNotNil(secondManifest["updatedAt"])
    }

    func testExistingDrpIsNotReplacedByPlaceholder() throws {
        let dest = try makeDir("dest")
        let template = tempDir.appendingPathComponent("szablon.drp")
        try "TEMPLATE".data(using: .utf8)!.write(to: template)

        var settings = Settings()
        settings.destinationRoot = dest.path
        settings.drpTemplatePath = template.path
        _ = try ProjectBuilder(settings: settings).build(projectName: "Wesele")

        settings.drpTemplatePath = nil
        let layout = try ProjectBuilder(settings: settings).build(projectName: "Wesele")

        XCTAssertEqual(try String(contentsOf: layout.drpFileURL(), encoding: .utf8), "TEMPLATE")
    }

    private func manifest(of layout: ProjectLayout) throws -> [String: Any] {
        let data = try Data(contentsOf: layout.manifestURL())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: – Kopiowanie

    func testFailedFileDoesNotStopIngest() throws {
        let card = try makeDir("card")
        let dest = try makeDir("dest")
        let good = card.appendingPathComponent("A002.MOV")
        try "dobry-klip".data(using: .utf8)!.write(to: good)
        let missing = MediaFile(url: card.appendingPathComponent("A001.MOV"), category: .video, size: 10)
        let files = [missing, MediaFile(url: good, category: .video, size: 10)]

        let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
        let report = try CopyService(verifyChecksums: false).copy(files: files, to: layout)

        XCTAssertEqual(report.totalFailed, 1)
        XCTAssertEqual(report.failed.first?.url.lastPathComponent, "A001.MOV")
        XCTAssertEqual(report.totalCopied, 1)
        XCTAssertTrue(fm.fileExists(atPath: layout.videoDir.appendingPathComponent("A002.MOV").path))
        XCTAssertFalse(fm.fileExists(atPath: layout.videoDir.appendingPathComponent("A001.MOV").path))
    }

    func testVerifiedCopyMatchesSourceAndKeepsDates() throws {
        let card = try makeDir("card")
        let dest = try makeDir("dest")
        let source = card.appendingPathComponent("C0001.MP4")
        let content = Data((0..<200_000).map { UInt8($0 % 251) })
        try content.write(to: source)
        let shotDate = Date(timeIntervalSince1970: 1_780_000_000)
        try fm.setAttributes([.modificationDate: shotDate], ofItemAtPath: source.path)

        let files = try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card)
        let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
        let report = try CopyService(verifyChecksums: false, verifyCopies: true).copy(files: files, to: layout)

        XCTAssertEqual(report.totalCopied, 1)
        XCTAssertEqual(report.totalVerified, 1)
        XCTAssertEqual(report.totalFailed, 0)
        let copy = layout.videoDir.appendingPathComponent("C0001.MP4")
        XCTAssertEqual(try Data(contentsOf: copy), content)
        let copiedDate = try fm.attributesOfItem(atPath: copy.path)[.modificationDate] as? Date
        XCTAssertEqual(copiedDate?.timeIntervalSince1970 ?? 0, shotDate.timeIntervalSince1970, accuracy: 1)
        // Żadnych pozostałości po plikach tymczasowych.
        let leftovers = try fm.contentsOfDirectory(atPath: layout.videoDir.path).filter { $0.hasSuffix(".part") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testReingestAfterNameCollisionDoesNotDuplicate() throws {
        // Dwie kamery z plikiem o tej samej nazwie, zgrywane do jednego folderu.
        let cardA = try makeDir("cardA")
        let cardB = try makeDir("cardB")
        let dest = try makeDir("dest")
        try "kamera-a".data(using: .utf8)!.write(to: cardA.appendingPathComponent("C0001.MP4"))
        try "kamera-b-dluzszy".data(using: .utf8)!.write(to: cardB.appendingPathComponent("C0001.MP4"))
        let filesA = try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: cardA)
        let filesB = try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: cardB)
        let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
        let service = CopyService(verifyChecksums: false)

        _ = try service.copy(files: filesA, to: layout)
        let firstB = try service.copy(files: filesB, to: layout)
        let againB = try service.copy(files: filesB, to: layout)
        let againA = try service.copy(files: filesA, to: layout)

        XCTAssertEqual(firstB.copied.map(\.lastPathComponent), ["C0001_1.MP4"])
        XCTAssertEqual(againB.totalCopied, 0)
        XCTAssertEqual(againB.totalSkipped, 1)
        XCTAssertEqual(againA.totalSkipped, 1)
        let names = try fm.contentsOfDirectory(atPath: layout.videoDir.path).filter { !$0.hasPrefix(".") }.sorted()
        XCTAssertEqual(names, ["C0001.MP4", "C0001_1.MP4"])
    }

    func testSameNameAndSizeButDifferentDateIsNotDuplicate() throws {
        // Różne ujęcia o stałym bitrate: ta sama nazwa i rozmiar, inna data nagrania.
        let card = try makeDir("card")
        let destDir = try makeDir("dest")
        let source = card.appendingPathComponent("A001.BRAW")
        try "AAAA".data(using: .utf8)!.write(to: source)
        let existing = destDir.appendingPathComponent("A001.BRAW")
        try "BBBB".data(using: .utf8)!.write(to: existing)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: existing.path)

        let decision = CopyPlanner.decision(
            source: source, destinationDirectory: destDir, verifyChecksums: false, existingNames: ["A001.BRAW"]
        )

        guard case .copy(let url) = decision else {
            return XCTFail("Expected copy with unique name, got \(decision)")
        }
        XCTAssertEqual(url.lastPathComponent, "A001_1.BRAW")
    }

    func testRepeatedIngestSkipsAlreadyCopiedFiles() throws {
        let card = try makeDir("card")
        let dest = try makeDir("dest")
        try "klip".data(using: .utf8)!.write(to: card.appendingPathComponent("A001.MOV"))
        let files = try MediaScanner(enabledExtensions: ["mov"]).scan(volumeRoot: card)
        let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")

        _ = try CopyService(verifyChecksums: false, verifyCopies: true).copy(files: files, to: layout)
        let second = try CopyService(verifyChecksums: false, verifyCopies: true).copy(files: files, to: layout)

        XCTAssertEqual(second.totalCopied, 0)
        XCTAssertEqual(second.totalSkipped, 1)
    }
}
