import XCTest
@testable import SDCardOrganizerCore

/// Wybór materiałów na karcie, katalog formatów i pomijanie katalogów systemowych kamer.
final class SelectionAndFormatsTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
    }

    private func makeCard() -> CardIngestConfig {
        var config = CardIngestConfig(volumeURL: URL(fileURLWithPath: "/Volumes/Card"), volumeName: "Card")
        let day1 = Date(timeIntervalSince1970: 1_780_000_000)
        let day2 = day1.addingTimeInterval(86_400 * 3)
        config.setScanResults([
            MediaFile(url: URL(fileURLWithPath: "/Volumes/Card/a.mov"), category: .video, size: 10, date: day1),
            MediaFile(url: URL(fileURLWithPath: "/Volumes/Card/b.mov"), category: .video, size: 10, date: day2),
            MediaFile(url: URL(fileURLWithPath: "/Volumes/Card/c.wav"), category: .audio, size: 5, date: day2)
        ])
        return config
    }

    // MARK: – Wybór dni i typów

    func testScanSelectsLatestDayOnly() {
        let config = makeCard()
        XCTAssertTrue(config.isLatestDayOnlySelected)
        XCTAssertFalse(config.areAllDaysSelected)
        XCTAssertEqual(config.filteredFiles.count, 2)
    }

    func testDeselectingAllDaysSelectsNothing() {
        var config = makeCard()
        config.selectedDays = []
        XCTAssertTrue(config.filteredFiles.isEmpty)
        XCTAssertEqual(config.totalSelectedBytes, 0)
        XCTAssertFalse(config.areAllDaysSelected)
    }

    func testAudioCanBeExcluded() {
        var config = makeCard()
        config.selectAllDays()
        XCTAssertTrue(config.areAllDaysSelected)
        XCTAssertEqual(config.filteredFiles.count, 3)
        config.includeAudio = false
        XCTAssertEqual(config.filteredFiles.map(\.url.lastPathComponent).sorted(), ["a.mov", "b.mov"])
    }

    // MARK: – Katalog formatów

    func testCatalogIsSingleSourceOfTruth() {
        XCTAssertEqual(Settings.defaultExtensions, MediaFormats.allExtensions.subtracting(["lrf"]))
        XCTAssertFalse(Settings().enabledExtensions.contains("lrf"))
        XCTAssertEqual(MediaCategory.category(for: URL(fileURLWithPath: "/a/clip.MPG")), .video)
        XCTAssertEqual(MediaCategory.category(for: URL(fileURLWithPath: "/a/shot.IIQ")), .photo)
        XCTAssertEqual(MediaCategory.category(for: URL(fileURLWithPath: "/a/take.flac")), .audio)
        XCTAssertEqual(MediaCategory.category(for: URL(fileURLWithPath: "/a/proxy.lrf")), .video)
    }

    func testDeselectingAllFileTypesSurvivesReload() throws {
        var settings = Settings()
        settings.enabledExtensions = []
        let url = tempDir.appendingPathComponent("settings.json")
        try SettingsStore.save(settings, to: url)

        XCTAssertEqual(try SettingsStore.load(from: url).enabledExtensions, [])
    }

    // MARK: – Skaner

    func testScannerSkipsCameraThumbnailFolders() throws {
        let clips = tempDir.appendingPathComponent("PRIVATE/M4ROOT/CLIP", isDirectory: true)
        let thumbnails = tempDir.appendingPathComponent("PRIVATE/M4ROOT/THMBNL", isDirectory: true)
        try fm.createDirectory(at: clips, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try "klip".data(using: .utf8)!.write(to: clips.appendingPathComponent("C0001.MP4"))
        try "miniatura".data(using: .utf8)!.write(to: thumbnails.appendingPathComponent("C0001T01.JPG"))
        try "zdjecie".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("DSC0001.JPG"))

        let results = try MediaScanner(enabledExtensions: ["mp4", "jpg"]).scan(volumeRoot: tempDir)

        XCTAssertEqual(results.map(\.url.lastPathComponent).sorted(), ["C0001.MP4", "DSC0001.JPG"])
    }
}
