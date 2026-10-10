import XCTest
@testable import SDCardOrganizerCore

/// Kopia zapasowa, pliki towarzyszące, raport zgrania i nowe pola ustawień.
final class BackupSidecarReportTests: XCTestCase {
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

    private func visibleNames(_ dir: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    // MARK: – Kopia zapasowa

    func testBackupGetsVerifiedCopyOfEveryFile() throws {
        let card = try makeDir("card")
        try Data(repeating: 7, count: 50_000).write(to: card.appendingPathComponent("C0001.MP4"))
        try Data(repeating: 9, count: 20_000).write(to: card.appendingPathComponent("DSC0001.JPG"))
        let files = try MediaScanner(enabledExtensions: ["mp4", "jpg"]).scan(volumeRoot: card)
        let primary = ProjectLayout(destinationRoot: try makeDir("ssd").path, projectName: "Test")
        let backup = ProjectLayout(destinationRoot: try makeDir("hdd").path, projectName: "Test")

        var progress: [CopyProgress] = []
        let service = CopyService(verifyChecksums: false, verifyCopies: true)
        service.onProgress = { progress.append($0) }
        let report = try service.copy(files: files, to: primary, cameraLabel: "Kamera A", backupLayout: backup)

        XCTAssertEqual(report.totalCopied, 2)
        XCTAssertEqual(report.backupCopied.count, 2)
        XCTAssertEqual(report.totalFailed, 0)
        XCTAssertEqual(report.checksums.count, 4, "Sumy dla kopii na obu dyskach")
        let backupClip = backup.targetDirectory(for: .video, cameraLabel: "Kamera A").appendingPathComponent("C0001.MP4")
        XCTAssertEqual(try Data(contentsOf: backupClip), Data(repeating: 7, count: 50_000))
        XCTAssertEqual(progress.last?.totalBytes, 140_000)
        XCTAssertEqual(progress.last?.fraction, 1)
    }

    func testBackupSkipsFilesAlreadyThere() throws {
        let card = try makeDir("card")
        try Data(repeating: 1, count: 1_000).write(to: card.appendingPathComponent("A001.MOV"))
        let files = try MediaScanner(enabledExtensions: ["mov"]).scan(volumeRoot: card)
        let primary = ProjectLayout(destinationRoot: try makeDir("ssd").path, projectName: "Test")
        let backup = ProjectLayout(destinationRoot: try makeDir("hdd").path, projectName: "Test")

        _ = try CopyService(verifyChecksums: false).copy(files: files, to: primary, backupLayout: backup)
        let again = try CopyService(verifyChecksums: false).copy(files: files, to: primary, backupLayout: backup)

        XCTAssertEqual(again.totalSkipped, 1)
        XCTAssertEqual(again.backupSkipped.count, 1)
        XCTAssertTrue(again.backupCopied.isEmpty)
    }

    // MARK: – Pliki towarzyszące

    func testSidecarDetection() {
        let media = URL(fileURLWithPath: "/card/M4ROOT/CLIP/C0001.MP4")
        let listing = ["C0001.MP4", "C0001M01.XML", "C0002M01.XML", "C00010M01.XML", "C0001.xmp", "C0001.THM", "C0001X.SRT"]

        let sidecars = CopyService.sidecarFiles(of: media, directoryListing: listing).map(\.lastPathComponent)

        XCTAssertEqual(sidecars, ["C0001.xmp", "C0001M01.XML"])
    }

    func testSidecarsFollowMediaNameIncludingCollisionSuffix() throws {
        let cardA = try makeDir("cardA")
        let cardB = try makeDir("cardB")
        try "a".data(using: .utf8)!.write(to: cardA.appendingPathComponent("DJI_0001.MP4"))
        try "bb".data(using: .utf8)!.write(to: cardB.appendingPathComponent("DJI_0001.MP4"))
        try "telemetria".data(using: .utf8)!.write(to: cardB.appendingPathComponent("DJI_0001.SRT"))
        let layout = ProjectLayout(destinationRoot: try makeDir("dest").path, projectName: "Test")
        let service = CopyService(verifyChecksums: false, copySidecars: true)

        _ = try service.copy(files: try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: cardA), to: layout)
        let report = try service.copy(files: try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: cardB), to: layout)

        XCTAssertEqual(report.sidecarsCopied.map(\.lastPathComponent), ["DJI_0001_1.SRT"])
        XCTAssertEqual(visibleNames(layout.videoDir), ["DJI_0001.MP4", "DJI_0001_1.MP4", "DJI_0001_1.SRT"])
    }

    func testSidecarsAreNotCopiedWhenDisabled() throws {
        let card = try makeDir("card")
        try "klip".data(using: .utf8)!.write(to: card.appendingPathComponent("C0001.MP4"))
        try "<xml/>".data(using: .utf8)!.write(to: card.appendingPathComponent("C0001M01.XML"))
        let layout = ProjectLayout(destinationRoot: try makeDir("dest").path, projectName: "Test")

        let report = try CopyService(verifyChecksums: false).copy(
            files: try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card), to: layout
        )

        XCTAssertTrue(report.sidecarsCopied.isEmpty)
        XCTAssertEqual(visibleNames(layout.videoDir), ["C0001.MP4"])
    }

    // MARK: – Raport zgrania

    func testReportWritesSummaryAndShasumCompatibleChecksums() throws {
        let card = try makeDir("card")
        try Data(repeating: 3, count: 4_096).write(to: card.appendingPathComponent("C0001.MP4"))
        let layout = ProjectLayout(destinationRoot: try makeDir("dest").path, projectName: "Wesele")
        let report = try CopyService(verifyChecksums: false, verifyCopies: true).copy(
            files: try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card),
            to: layout,
            cameraLabel: "Kamera A"
        )

        let written = try IngestReportWriter.write(
            projectRoot: layout.root,
            projectName: "Wesele",
            sections: [.init(title: "Kamera A (SD)", report: report)],
            wasCancelled: false,
            date: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let summary = try String(contentsOf: written.summary, encoding: .utf8)
        XCTAssertTrue(summary.contains("Projekt: Wesele"))
        XCTAssertTrue(summary.contains("Status: zakończone pomyślnie"))
        XCTAssertTrue(summary.contains("[Kamera A (SD)]"))

        let checksumsURL = try XCTUnwrap(written.checksums)
        let lines = try String(contentsOf: checksumsURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let expectedHash = try CopyService.checksum(of: card.appendingPathComponent("C0001.MP4"), bypassingCache: false)
        XCTAssertEqual(String(lines[0]), "\(expectedHash)  Video/Kamera A/C0001.MP4")
    }

    func testReportWithoutVerificationHasNoChecksumFile() throws {
        let root = try makeDir("projekt")
        let written = try IngestReportWriter.write(
            projectRoot: root, projectName: "Test", sections: [], wasCancelled: true
        )
        XCTAssertNil(written.checksums)
        XCTAssertTrue(try String(contentsOf: written.summary, encoding: .utf8).contains("przerwane"))
    }

    // MARK: – Ustawienia

    func testNewSettingsDefaultsAndMigration() throws {
        let defaults = Settings()
        XCTAssertEqual(defaults.backupDestinationRoot, "")
        XCTAssertFalse(defaults.ejectCardsAfterIngest)
        XCTAssertTrue(defaults.copySidecarFiles)
        XCTAssertTrue(defaults.writeIngestReport)
        XCTAssertEqual(defaults.menuBarIconStyle, .automatic)

        let url = tempDir.appendingPathComponent("settings.json")
        try #"{"destinationRoot":"/Volumes/SSD","menuBarIconStyle":"nieznany"}"#.data(using: .utf8)!.write(to: url)
        let loaded = try SettingsStore.load(from: url)
        XCTAssertEqual(loaded.destinationRoot, "/Volumes/SSD")
        XCTAssertEqual(loaded.menuBarIconStyle, .automatic)

        var custom = Settings()
        custom.menuBarIconStyle = .custom
        custom.customMenuBarIconPath = "/tmp/ikona.png"
        custom.backupDestinationRoot = "/Volumes/HDD"
        try SettingsStore.save(custom, to: url)
        XCTAssertEqual(try SettingsStore.load(from: url), custom)
    }
}
